module AMR = Atomic_markable_reference

let bottom_level = 0

type node = {
  key : int;
  top_level : int;
  next : node AMR.list array;
}

type list = {
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
  let rec retry () =
    let pred = ref t.head in
    let restart = ref false in

    for level = t.max_level downto bottom_level do
      if not !restart then begin
        let marked = ref false in
        let curr = ref (AMR.get_reference ((!pred).next.(level))) in

        let rec scan () =
          if not !restart then begin
            let succ = AMR.get ((!curr).next.(level)) marked in

            if !marked then begin
              (* curr is marked, try to unlink it *)
              let delete=
                AMR.compare_and_set ((!pred).next.(level))
                  ~expected_ref:!curr ~new_ref:succ
                  ~expected_mark:false ~new_mark:false
              in
              if not delete then
                (* CAS failed, something changed, restart whole find *)
                restart := true
              else begin
                (* delete worked, reread curr from pred *)
                curr := AMR.get_reference ((!pred).next.(level));
                scan ()
              end
            end
            else if (!curr).key < key then begin
              (* move right *)
              pred := !curr;
              curr := succ;
              scan ()
            end
            (* else curr.key >= key, stop this level *)
          end
        in

        scan ();

        if not !restart then begin
          preds.(level) <- !pred;
          succs.(level) <- !curr
        end
      end
    done;

    if !restart then retry ()
    else succs.(bottom_level).key = key
  in
  retry ()

(** [add s x] inserts key [x] into [s] if it is not already present.
    Returns [true] if [x] was added, and [false] if [x] was already present. *)
let add t key =
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in

  let rec attempt () =
    if find t key preds succs then
      false
    else begin
      let top_level = random_level t.max_level in
      let new_node = make_node key top_level succs in
      let pred = preds.(bottom_level) in
      let succ = succs.(bottom_level) in

      if not (AMR.compare_and_set pred.next.(bottom_level)
                ~expected_ref:succ ~new_ref:new_node
                ~expected_mark:false ~new_mark:false)
      then
        (* bottom level insert failed, retry *)
        attempt ()
      else begin
        (* bottom level linked, now link upper levels *)
        for level = bottom_level + 1 to top_level do
          let rec splice () =
            let pred = preds.(level) in
            let succ = succs.(level) in
            if AMR.compare_and_set pred.next.(level)
                 ~expected_ref:succ ~new_ref:new_node
                 ~expected_mark:false ~new_mark:false
            then
              ()
            else begin
              (* level changed, refresh preds/succs and retry this level *)
              ignore (find t key preds succs);
              splice ()
            end
          in
          splice ()
        done;
        true
      end
    end
  in
  attempt ()

(** [remove s x] removes key [x] from [s] if it is present.
    Returns [true] if [x] was removed, and [false] if [x] was not present. *)
let remove t key =
  let preds = Array.make (t.max_level + 1) t.head in
  let succs = Array.make (t.max_level + 1) t.tail in

  let rec attempt () =
    if not (find t key preds succs) then
      false
    else begin
      let node_to_remove = succs.(bottom_level) in

      (* mark upper levels first *)
      for level = node_to_remove.top_level downto bottom_level + 1 do
        let marked = ref false in
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

      (* bottom level mark is the actual remove point *)
      let marked = ref false in
      let rec mark_bottom () =
        let succ = AMR.get node_to_remove.next.(bottom_level) marked in
        let i_marked_it =
          AMR.compare_and_set node_to_remove.next.(bottom_level)
            ~expected_ref:succ ~new_ref:succ
            ~expected_mark:false ~new_mark:true
        in
        ignore (AMR.get node_to_remove.next.(bottom_level) marked);
        if i_marked_it then begin
          (* help cleanup *)
          ignore (find t key preds succs);
          true
        end
        else if !marked then
          false
        else
          (* succ changed, retry bottom mark *)
          mark_bottom ()
      in
      mark_bottom ()
    end
  in
  attempt ()

(** [contains s x] returns [true] if key [x] is present in [s],
    and [false] otherwise. *)
let contains t key =
  let pred = ref t.head in
  let curr = ref t.tail in
  let succ = ref t.tail in
  let marked = ref false in

  for level = t.max_level downto bottom_level do
    curr := AMR.get_reference ((!pred).next.(level));

    let rec scan () =
      succ := AMR.get ((!curr).next.(level)) marked;

      let rec skip_marked () =
        if !marked then begin
          (* reread from pred *)
          curr := AMR.get_reference ((!pred).next.(level));
          succ := AMR.get ((!curr).next.(level)) marked;
          skip_marked ()
        end
      in

      skip_marked ();

      if (!curr).key < key then begin
        (* move right *)
        pred := !curr;
        curr := !succ;
        scan ()
      end
      (* else curr.key >= key, go one level down *)
    in

    scan ()
  done;

  (!curr).key = key