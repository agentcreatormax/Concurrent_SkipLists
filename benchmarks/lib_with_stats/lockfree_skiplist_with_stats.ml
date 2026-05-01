module AMR = Atomic_markable_ref


type node = {
  key : int;
  top_level : int;
  next : node AMR.t array;
}

type t = {
  head : node;
  tail : node;
  max_level : int;
}

(* returns a random level in [0, max_level - 1]
   head and tail alone stay at full height *)
let random_level max_level =
  let rec loop lvl bits =
    if lvl >= max_level - 1 then lvl
    else if bits land 1 = 1 then loop (lvl + 1) (bits lsr 1)
    else lvl
  in
  loop 0 (Random.bits ())

(** [create max_level] creates an empty lock-free skip list with maximum level
    [max_level].
    @raise Invalid_argument if [max_level < 0] *)
let create max_level =
  if max_level < 0 then
    invalid_arg "max_level must be non-negative"
  else
    let dummy_ref = Obj.magic () in
    let tail = {
      key = max_int;
      top_level = max_level;
      next = Array.init (max_level + 1) (fun _ -> AMR.create dummy_ref false);
    } in

    (* make tail.next[i] point to tail itself *)
    Array.iter
      (fun cell ->
        ignore
          (AMR.compare_and_set cell
             ~expected_ref:dummy_ref ~new_ref:tail
             ~expected_mark:false ~new_mark:false))
      tail.next;

    let head = {
      key = min_int;
      top_level = max_level;
      next = Array.init (max_level + 1) (fun _ -> AMR.create tail false);
    } in
    { head; tail; max_level }

(* makes node with next pointers initialized from succs *)
let make_node key top_level succs =
  {
    key;
    top_level;
    next =
      Array.init (top_level + 1) (fun level -> AMR.create succs.(level) false);
  }

(* find position of key
   fills preds[level] and succs[level]
   also deletes marked nodes while traversing *)
let find t key preds succs =
  let count = ref 0 in
  let pred = ref t.head in
  let marked = ref false in
  let curr = ref t.head in

  let rec retry () =
    let bottom_level=0 in
    pred := t.head;
    marked := false;

    try
    for level = t.max_level downto bottom_level do
        marked := false;
        curr := (AMR.get_reference ((!pred).next.(level)));

        let rec scan () =
            let succ = AMR.get ((!curr).next.(level)) marked in

            if !marked then begin
              (* curr is marked, try to unlink it *)
              let delete =
                AMR.compare_and_set ((!pred).next.(level))
                  ~expected_ref:!curr ~new_ref:succ
                  ~expected_mark:false ~new_mark:false
              in
              if not delete then
                (* CAS failed, something changed, restart whole find *)
                raise Exit
              else begin
                (* delete worked, reread curr from pred *)
                curr := AMR.get_reference ((!pred).next.(level));
                incr count;
                scan ()
              end
            end
            else if (!curr).key < key then begin
              (* move right *)
              pred := !curr;
              curr := succ;
              incr count;
              scan ()
            end
            (* else curr.key >= key, stop this level *)
          (* end *)
        in scan ();

        preds.(level) <- !pred;
        succs.(level) <- !curr
    done;

    succs.(bottom_level).key = key
    with Exit -> (Domain.cpu_relax(); retry())

  in
  let output = retry () in
  (output, !count)

(** [add s x] inserts key [x] into [s] if it is not already present.
    Returns [true] if [x] was added, and [false] if [x] was already present. *)
let add t key =
  let bottom_level=0 in
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in
  let count = ref 0 in

  let node_marked = ref false in
  let level = ref (bottom_level + 1) in
  let marked = ref false in

  let rec attempt () =
    let (bool_val, count_m) = find t key preds succs in
    count := !count + count_m;

    if bool_val then
      false
    else begin
      let top_level = random_level t.max_level in
      let new_node = make_node key top_level succs in
      let pred = preds.(bottom_level) in
      let succ = succs.(bottom_level) in

      if not (AMR.compare_and_set pred.next.(bottom_level)
                ~expected_ref:succ ~new_ref:new_node
                ~expected_mark:false ~new_mark:false)
      then (
        (* bottom level insert failed, retry *)
        Domain.cpu_relax ();
        attempt ())
      else begin
        (* bottom-level CAS is the add linearization point *)
        node_marked := false;
        level := (bottom_level + 1);

        while !level <= top_level && not !node_marked do
          let rec splice () =
            marked := false;
            ignore (AMR.get new_node.next.(bottom_level) marked);

            if !marked then
              (* node already got removed, stop linking upper levels *)
              node_marked := true
            else begin
              let pred = preds.(!level) in
              let succ = succs.(!level) in

              if AMR.compare_and_set pred.next.(!level)
                   ~expected_ref:succ ~new_ref:new_node
                   ~expected_mark:false ~new_mark:false
              then
                ()
              else begin
                (* level changed, refresh preds/succs and retry this level *)
                let (_, count_m) = find t key preds succs in
                count := !count + count_m;
                splice ()
              end
            end
          in
          splice ();
          incr level
        done;
        true
      end
    end
  in
  let output = attempt () in
  (output, !count)

(** [remove s x] removes key [x] from [s] if it is present.
    Returns [true] if [x] was removed, and [false] if [x] was not present. *)
let remove t key =
  let bottom_level=0 in
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in
  let count = ref 0 in
  let marked = ref false in

  let attempt () =
    let (bool_val, count_) = find t key preds succs in
    count := !count + count_;

    if not bool_val then
      false
    else begin
      let node_to_remove = succs.(bottom_level) in

      (* mark upper levels first *)
      for level = node_to_remove.top_level downto bottom_level + 1 do
        marked := false;
        let rec mark_level () =
          let succ = AMR.get node_to_remove.next.(level) marked in
          if not !marked then begin
            ignore
              (AMR.compare_and_set node_to_remove.next.(level)
                 ~expected_ref:succ ~new_ref:succ
                 ~expected_mark:false ~new_mark:true);
            (* reread mark; retry till this level gets marked *)
            ignore (AMR.get node_to_remove.next.(level) marked);

            if not !marked then mark_level ()
          end
        in
        mark_level ()
      done;

      (* bottom level mark is the linearization point of a successful remove.
         We read the current succ from node_to_remove.next[0] before the CAS,
         then refresh it afterwards (matching Java's
           succ = succs[0].next[0].get(marked)
         which is the same cell).  This ensures succ is never stale on retry. *)
      marked := false;
      let succ = ref (AMR.get node_to_remove.next.(bottom_level) marked) in

      let rec mark_bottom () =
        let i_marked_it =
          AMR.compare_and_set node_to_remove.next.(bottom_level)
            ~expected_ref:!succ ~new_ref:!succ
            ~expected_mark:false ~new_mark:true
        in
        (* refresh succ + mark so the next iteration uses the latest pointer *)
        succ := AMR.get node_to_remove.next.(bottom_level) marked;
       

        if i_marked_it then begin
          (* help cleanup *)
          let (_, count_) = find t key preds succs in
          count := !count + count_;
          true
        end
        else if !marked then
          (* another thread already marked it, we lost the race *)
          false
        else
          (* CAS failed but node still unmarked: succ changed, retry *)
          mark_bottom ()
      in
      mark_bottom ()
    end
  in
  let output = attempt () in
  (output, !count)

(** [contains s x] returns [true] if key [x] is present in [s],
    and [false] otherwise. *)
let contains t key =
  let bottom_level=0 in
  let pred = ref t.head in
  let curr = ref t.tail in
  let succ = ref t.tail in
  let marked = ref false in
  let count = ref 0 in

  for level = t.max_level downto bottom_level do
    curr := AMR.get_reference ((!pred).next.(level));

    let rec scan () =
      succ := AMR.get ((!curr).next.(level)) marked;

      let rec skip_marked () =
        if !marked then begin
          (* jump over marked nodes *)
          curr := !succ;
          succ := AMR.get ((!curr).next.(level)) marked;
          incr count;
          skip_marked ()
        end
      in

      skip_marked ();

      if (!curr).key < key then begin
        pred := !curr;
        curr := !succ;
        incr count;
        scan ()
      end
       (* else curr.key >= key, go one level down *)
    in

    scan ()
  done;

  let bool_val = (!curr).key = key in
  (bool_val, !count)
