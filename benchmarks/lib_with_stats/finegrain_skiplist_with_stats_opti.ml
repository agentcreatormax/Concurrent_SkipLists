(* ===================================================================
   Fine-Grained Locking Skip List
   =================================================================== *)

let bottom_level = 0

type node = {
  key          : int;
  top_level    : int;
  next         : node option Atomic.t array;  (* next.(i) = successor at level i *)
  lock         : Mutex.t;            (* per-node lock *)
  marked       : bool Atomic.t;           (* logical deletion flag *)
  fully_linked : bool Atomic.t;           (* becomes true once node is visible *)
}

type t = {
  head      : node;
  tail      : node;
  max_level : int;
}

(* ------------------------------------------------------------------ *)
(* Random level                                                       *)
(* ------------------------------------------------------------------ *)

let random_level max_level =
  let rec loop lvl bits =
    if lvl >= max_level - 1 then lvl
    else if bits land 1 = 1 then loop (lvl + 1) (bits lsr 1)
    else lvl
  in
  loop 0 (Random.bits ())

(* ------------------------------------------------------------------ *)
(* Node construction                                                  *)
(* ------------------------------------------------------------------ *)

let make_node key top_level =
  {
    key;
    top_level;
    next = Array.init (top_level + 1) (fun _ -> Atomic.make None);
    lock         = Mutex.create ();
    marked       = Atomic.make false;
    fully_linked  = Atomic.make false;
  }

let create max_level =
  if max_level < 0 then
    invalid_arg "max_level must be non-negative"
  else
    let tail = make_node max_int max_level in
    let head = make_node min_int max_level in
    Array.iter (fun cell -> Atomic.set cell (Some tail)) head.next;
    Atomic.set tail.fully_linked true;
    Atomic.set head.fully_linked true;
    { head; tail; max_level }

(* ------------------------------------------------------------------ *)
(* find                                                               *)
(* ------------------------------------------------------------------ *)

let find t key preds succs =
  let count = ref 0 in
  let found = ref (-1) in
  let pred  = ref t.head in
  let curr = ref t.head in

  for level = t.max_level downto bottom_level do
    curr := (Option.get (Atomic.get !pred.next.(level)));
    incr count;
    while !curr.key < key do
      pred := !curr;
      curr := Option.get (Atomic.get !curr.next.(level));
      incr count
    done;
    if !found = -1 && !curr.key = key then
      found := level;
    preds.(level) <- !pred;
    succs.(level) <- !curr
  done;

  (!found, !count)

(* ------------------------------------------------------------------ *)
(* Lock helpers                                                       *)
(* ------------------------------------------------------------------ *)

let lock_unique_sorted preds top_level =
  let seen = ref [] in
  for level = bottom_level to top_level do
    let pred = preds.(level) in
    if not (List.exists (fun n -> n == pred) !seen) then
      seen := pred :: !seen
  done;
  let sorted = List.sort (fun a b -> compare a.key b.key) !seen in
  List.iter (fun n -> Mutex.lock n.lock) sorted;
  sorted

let unlock_all nodes =
  List.iter (fun n -> Mutex.unlock n.lock) nodes
(* ------------------------------------------------------------------ *)
(* contains  -- no locks                                                *)
(* ------------------------------------------------------------------ *)

let contains t key =
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in
  let (level_found, count) = find t key preds succs in
  let bool_val = level_found >= 0
  && Atomic.get succs.(level_found).fully_linked
  && not (Atomic.get succs.(level_found).marked) in
  (bool_val, count)

(* ------------------------------------------------------------------ *)
(* add                                                                *)
(* ------------------------------------------------------------------ *)

let add t key =
  let top_level = random_level t.max_level in
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in
  let count = ref 0 in
  let valid = ref true in

  let rec attempt () =
    let (level_found, count_) = find t key preds succs in
    count := !count + count_;

    if level_found >= 0 then begin
      (* Key already exists at some level. *)
      let node_found = succs.(level_found) in
      if not (Atomic.get (node_found.marked)) then begin
        (* Wait until the existing node becomes fully visible.
           This is optimistic waiting, not locking. *)
        while not (Atomic.get (node_found.fully_linked))
           && not (Atomic.get (node_found.marked)) do
          Domain.cpu_relax ()
        done;
        if (Atomic.get (node_found.marked)) then
          attempt ()   (* node vanished while we waited, retry *)
        else
          false        (* already present *)
      end else
        attempt ()     (* being removed concurrently, retry *)
    end else begin
      (* Lock each distinct predecessor once, in a consistent order. *)
      let locked = lock_unique_sorted preds top_level in

      (* Validate that:
         - none of the locked predecessors got marked
         - each pred still points to the same succ we found earlier *)
      valid := true;
      begin
        try
          for level = bottom_level to top_level do
            let pred = preds.(level) in
            let succ = succs.(level) in
            if Atomic.get pred.marked then begin
              valid := false;
              raise Exit
            end;
            match Atomic.get pred.next.(level) with
            | Some n when n == succ -> ()
            | _ ->
                valid := false;
                raise Exit
          done
        with Exit -> ()
      end;

      if not !valid then begin
        unlock_all locked;
        attempt ()
      end else begin
        (* Splice new node into every level it participates in. *)
        let new_node = make_node key top_level in
        for level = bottom_level to top_level do
          Atomic.set new_node.next.(level) (Some succs.(level));
          Atomic.set preds.(level).next.(level) (Some new_node) 
        done;

        (* Publishing point: node is now visible to readers. *)
        Atomic.set new_node.fully_linked true;

        unlock_all locked;
        true
      end
    end
  in
  let output = attempt () in
  (output, !count)

(* ------------------------------------------------------------------ *)
(* remove                                                             *)
(* ------------------------------------------------------------------ *)

let remove t key =
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in
  let count = ref 0 in

  let find_and_mark () =
    let (level_found, count_) = find t key preds succs in
    count := !count + count_;
    if level_found < 0 then
      None
    else begin
      let candidate = succs.(level_found) in
      if not (Atomic.get candidate.fully_linked) || (Atomic.get candidate.marked) then
        None
      else begin
        Mutex.lock candidate.lock;
        if (Atomic.get candidate.marked) then begin
          Mutex.unlock candidate.lock;
          None
        end else begin
          Atomic.set candidate.marked true;
          Mutex.unlock candidate.lock;
          Some candidate
        end
      end
    end
  in

  let rec physical_remove victim =
    (* Refresh predecessors/successors after marking. *)
    let (_, count_) = find t key preds succs in
    count := !count + count_;

    let top = victim.top_level in
    let locked = lock_unique_sorted preds top in

    (* Validate that the victim is still immediately after each pred. *)
    let valid = ref true in
    begin
      try
        for level = bottom_level to top do
          let pred = preds.(level) in
          if Atomic.get pred.marked then begin
            valid := false;
            raise Exit
          end;
          match Atomic.get pred.next.(level) with
          | Some n when n == victim -> ()
          | _ ->
              valid := false;
              raise Exit
        done
      with Exit -> ()
    end;

    if not !valid then begin
      unlock_all locked;
      physical_remove victim
    end else begin
      (* Physically unlink from top level down to level 0. *)
      for level = top downto bottom_level do
        Atomic.set preds.(level).next.(level) (Atomic.get victim.next.(level))
      done;

      unlock_all locked;
      true
    end
  in

  let bool_val = 
    match find_and_mark () with
    | None -> false
    | Some victim -> physical_remove victim in
  
  (bool_val, !count)