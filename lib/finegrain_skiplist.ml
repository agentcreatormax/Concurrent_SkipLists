(* ===================================================================
   Fine-Grained Locking Skip List

   Each node has its own Mutex.
   add / remove lock predecessor nodes bottom-up, validate, then splice.
   contains is optimistic — no locks taken.
   =================================================================== *)

let bottom_level = 0

type node = {
  key       : int;
  top_level : int;
  next      : node option array;  (* next.(i) = successor at level i *)
  lock      : Mutex.t;
  marked    : bool ref;           (* logically deleted *)
  fully_linked : bool ref;        (* visible once linked at all levels *)
}

type t = {
  head      : node;
  tail      : node;
  max_level : int;
}

(* ------------------------------------------------------------------ *)
(*  Random level      *)
(* ------------------------------------------------------------------ *)

let random_level max_level =
  let rec loop lvl bits =
    if lvl >= max_level - 1 then lvl
    else if bits land 1 = 1 then loop (lvl + 1) (bits lsr 1)
    else lvl
  in
  loop 0 (Random.bits ())

(* ------------------------------------------------------------------ *)
(*  Helpers                                                             *)
(* ------------------------------------------------------------------ *)

let make_node key top_level =
  { key;
    top_level;
    next         = Array.make (top_level + 1) None;
    lock         = Mutex.create ();
    marked       = ref false;
    fully_linked = ref false; }

let create max_level =
  if max_level < 0 then
    invalid_arg "max_level must be non-negative"
  else
    let tail = make_node max_int max_level in
    let head = make_node min_int max_level in
    (* every level of head points to tail *)
    Array.fill head.next 0 (max_level + 1) (Some tail);
    tail.fully_linked := true;
    head.fully_linked := true;
    { head; tail; max_level }

(* ------------------------------------------------------------------ *)
(*  find — locate predecessor/successor at every level                 *)
(*  Returns the level at which key was found (-1 if absent).          *)
(*  No locks taken.                                                    *)
(* ------------------------------------------------------------------ *)

let find t key preds succs =
  let found = ref (-1) in
  let pred  = ref t.head in
  for level = t.max_level downto bottom_level do
    let curr = ref (Option.get !pred.next.(level)) in
    while !curr.key < key do
      pred := !curr;
      curr := Option.get !curr.next.(level)
    done;
    if !found = -1 && !curr.key = key then found := level;
    preds.(level) <- !pred;
    succs.(level) <- !curr
  done;
  !found

(* ------------------------------------------------------------------ *)
(*  contains — no locks                                              *)
(* ------------------------------------------------------------------ *)

let contains t key =
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in
  let level_found = find t key preds succs in
  level_found >= 0
  && !(succs.(level_found).fully_linked)
  && not !(succs.(level_found).marked)

(* ------------------------------------------------------------------ *)
(*  add                                                                 *)
(*                                                                      *)
(*  1. find preds/succs                                                *)
(*  2. if key present and fully linked and not marked → already there  *)
(*  3. lock preds bottom-up, validate, splice, mark fully_linked       *)
(* ------------------------------------------------------------------ *)

let add t key =
  let top_level = random_level t.max_level in
  let preds     = Array.make (t.max_level + 1) t.head in
  let succs     = Array.make (t.max_level + 1) t.tail in
  let rec attempt () =
    let level_found = find t key preds succs in
    if level_found >= 0 then begin
      (* key already exists in the list *)
      let node_found = succs.(level_found) in
      if not !(node_found.marked) then begin
        (* wait until it is fully linked — spin *)
        while not !(node_found.fully_linked) do () done;
        false   (* already present *)
      end else
        attempt ()   (* being removed concurrently, retry *)
    end else begin
      (* --- Lock predecessors bottom-up --- *)
      let highest_locked = ref (-1) in
      let valid = ref true in
      begin try
        for level = bottom_level to top_level do
          let pred = preds.(level) in
          let succ = succs.(level) in
          Mutex.lock pred.lock;
          highest_locked := level;
          (* validate: pred not marked AND pred still points to succ *)
          if !(pred.marked) || pred.next.(level) <> Some succ then begin
            valid := false;
            raise Exit
          end
        done
      with Exit -> () end;
      if not !valid then begin
        (* unlock and retry *)
        for level = !highest_locked downto bottom_level do
          Mutex.unlock preds.(level).lock
        done;
        attempt ()
      end else begin
        (* --- Splice in --- *)
        let new_node = make_node key top_level in
        for level = bottom_level to top_level do
          new_node.next.(level) <- Some succs.(level);
          preds.(level).next.(level) <- Some new_node
        done;
        new_node.fully_linked := true;
        (* --- Unlock --- *)
        for level = !highest_locked downto bottom_level do
          Mutex.unlock preds.(level).lock
        done;
        true
      end
    end
  in
  attempt ()

(* ------------------------------------------------------------------ *)
(*  remove                                                              *)
(*                                                                      *)
(*  1. find victim                                                     *)
(*  2. lock victim, mark it (logical deletion)                         *)
(*  3. lock preds, validate, splice out, unlock                        *)
(* ------------------------------------------------------------------ *)

let remove t key =
  let preds  = Array.make (t.max_level + 1) t.head in
  let succs  = Array.make (t.max_level + 1) t.tail in
  let victim = ref None in
  let is_marked = ref false in
  let rec attempt () =
    let level_found = find t key preds succs in
    (* decide whether we own the logical deletion *)
    let can_delete =
      match !victim with
      | Some v -> not !is_marked && v == succs.(bottom_level)
      | None   ->
        level_found >= 0
        && !(succs.(level_found).fully_linked)
        && succs.(level_found).top_level = level_found
        && not !(succs.(level_found).marked)
    in
    if not can_delete then
      (* key absent or already being removed *)
      !is_marked   (* if we marked it ourselves earlier, return true *)
    else begin
      let node =
        match !victim with
        | Some v -> v
        | None   ->
          let v = succs.(level_found) in
          victim := Some v;
          v
      in
      (* --- Logically delete: lock node and mark --- *)
      if not !is_marked then begin
        Mutex.lock node.lock;
        if !(node.marked) then begin
          Mutex.unlock node.lock;
          false   (* lost the race *)
        end else begin
          node.marked := true;
          is_marked := true;
          Mutex.unlock node.lock;
          (* fall through to physical removal *)
          let top = node.top_level in
          let highest_locked = ref (-1) in
          let valid = ref true in
          begin try
            for level = bottom_level to top do
              let pred = preds.(level) in
              Mutex.lock pred.lock;
              highest_locked := level;
              if !(pred.marked) || pred.next.(level) <> Some node then begin
                valid := false;
                raise Exit
              end
            done
          with Exit -> () end;
          if not !valid then begin
            for level = !highest_locked downto bottom_level do
              Mutex.unlock preds.(level).lock
            done;
            attempt ()
          end else begin
            for level = top downto bottom_level do
              preds.(level).next.(level) <- node.next.(level)
            done;
            for level = !highest_locked downto bottom_level do
              Mutex.unlock preds.(level).lock
            done;
            true
          end
        end
      end else
        false
    end
  in
  attempt ()