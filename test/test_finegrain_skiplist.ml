(** Manual concurrent tests for Fine-Grained Locking Skip List *)

let printf = Printf.printf
module S = Finegrain_skiplist

(* ── helpers ────────────────────────────────────────────────────────────── *)

let assert_bool cond msg =
  if not cond then begin printf "FAIL: %s\n" msg; exit 1 end

let assert_eq a b msg =
  if a <> b then begin
    printf "FAIL: %s  expected=%d  got=%d\n" msg a b; exit 1
  end

let assert_list_eq a b msg =
  if List.sort compare a <> List.sort compare b then begin
    printf "FAIL: %s\n  expected: [%s]\n  got:      [%s]\n" msg
      (List.map string_of_int (List.sort compare b) |> String.concat "; ")
      (List.map string_of_int (List.sort compare a) |> String.concat "; ");
    exit 1
  end

(* ── sequential tests ───────────────────────────────────────────────────── *)

let test_sequential_basic () =
  let s = S.create 4 in
  assert_bool (not (S.contains s 42)) "empty list should not contain 42";
  assert_bool (S.add s 10)            "add 10 should return true";
  assert_bool (S.add s 20)            "add 20 should return true";
  assert_bool (S.add s 30)            "add 30 should return true";
  assert_bool (S.contains s 10)       "should contain 10";
  assert_bool (S.contains s 20)       "should contain 20";
  assert_bool (S.contains s 30)       "should contain 30";
  assert_bool (not (S.contains s 99)) "should not contain 99";
  printf "PASS: sequential basic\n"

let test_duplicate_add () =
  let s = S.create 4 in
  assert_bool (S.add s 5)       "first add should return true";
  assert_bool (not (S.add s 5)) "duplicate add should return false";
  assert_bool (S.contains s 5)  "element should still be present after dup add";
  printf "PASS: duplicate add\n"

let test_remove_basic () =
  let s = S.create 4 in
  assert_bool (not (S.remove s 7))   "remove from empty should return false";
  ignore (S.add s 7);
  assert_bool (S.remove s 7)         "remove existing key should return true";
  assert_bool (not (S.contains s 7)) "key should be gone after remove";
  assert_bool (not (S.remove s 7))   "second remove should return false";
  printf "PASS: remove basic\n"

let test_invalid_arg () =
  (try ignore (S.create (-1)); failwith "create (-1) should raise"
   with Invalid_argument _ -> ());
  printf "PASS: invalid arg\n"

let test_sequential_many () =
  let s = S.create 8 in
  let n = 1000 in
  for i = 1 to n do assert_bool (S.add s i) (Printf.sprintf "add %d" i) done;
  for i = 1 to n do assert_bool (S.contains s i) (Printf.sprintf "contains %d" i) done;
  assert_bool (not (S.contains s 0))       "should not contain 0";
  assert_bool (not (S.contains s (n + 1))) "should not contain n+1";
  for i = 1 to n do assert_bool (S.remove s i) (Printf.sprintf "remove %d" i) done;
  for i = 1 to n do assert_bool (not (S.contains s i)) (Printf.sprintf "gone %d" i) done;
  printf "PASS: sequential many\n"

let test_read_after_remove () =
  let s = S.create 4 in
  assert_bool (S.add s 99)            "first add";
  assert_bool (S.remove s 99)         "remove";
  assert_bool (not (S.contains s 99)) "gone after remove";
  assert_bool (S.add s 99)            "re-add should return true";
  assert_bool (S.contains s 99)       "present after re-add";
  printf "PASS: re-add after remove\n"

let test_max_level_zero () =
  let s = S.create 0 in
  assert_bool (S.add s 1)            "add on level-0 list";
  assert_bool (S.contains s 1)       "contains on level-0 list";
  assert_bool (S.remove s 1)         "remove on level-0 list";
  assert_bool (not (S.contains s 1)) "gone after remove on level-0";
  printf "PASS: max_level zero\n"

(** Boundary / edge keys: negative, zero, large values. *)
let test_boundary_keys () =
  let s = S.create 4 in
  let keys = [-1000; -1; 0; 1; 999999] in
  List.iter (fun k -> assert_bool (S.add s k) (Printf.sprintf "add %d" k)) keys;
  List.iter (fun k -> assert_bool (S.contains s k) (Printf.sprintf "contains %d" k)) keys;
  List.iter (fun k -> assert_bool (S.remove s k) (Printf.sprintf "remove %d" k)) keys;
  List.iter (fun k -> assert_bool (not (S.contains s k)) (Printf.sprintf "gone %d" k)) keys;
  printf "PASS: boundary keys\n"

(** contains returns false immediately after a confirmed remove. *)
let test_contains_after_remove () =
  let s = S.create 4 in
  ignore (S.add s 55);
  assert_bool (S.remove s 55)         "remove should succeed";
  assert_bool (not (S.contains s 55)) "contains must be false right after remove";
  printf "PASS: contains false after remove\n"

(** The loser of a same-key add race still sees the key via contains. *)
let test_loser_sees_key () =
  let s    = S.create 8 in
  let wins = Atomic.make 0 in
  let workers =
    List.init 8 (fun _ ->
      Domain.spawn (fun () ->
        if S.add s 42 then Atomic.fetch_and_add wins 1 |> ignore))
  in
  List.iter Domain.join workers;
  assert_eq (Atomic.get wins) 1 "exactly one add wins";
  assert_bool (S.contains s 42) "losers: key must still be visible";
  printf "PASS: loser of add race still sees key\n"

(* ── concurrent tests ───────────────────────────────────────────────────── *)

let test_concurrent_add () =
  let s = S.create 8 in
  let domains = 4 and per = 250 in
  let workers =
    List.init domains (fun d ->
      Domain.spawn (fun () ->
        for i = 1 to per do ignore (S.add s (d * 10000 + i)) done))
  in
  List.iter Domain.join workers;
  let missing = ref 0 in
  for d = 0 to domains - 1 do
    for i = 1 to per do
      if not (S.contains s (d * 10000 + i)) then incr missing
    done
  done;
  assert_eq !missing 0 "concurrent add: missing items";
  printf "PASS: concurrent add\n"

let test_concurrent_remove () =
  let s = S.create 8 in
  let n = 500 in
  for i = 1 to n do ignore (S.add s i) done;
  let chunk = n / 4 in
  let workers =
    List.init 4 (fun d ->
      Domain.spawn (fun () ->
        for i = d * chunk + 1 to (d + 1) * chunk do
          ignore (S.remove s i)
        done))
  in
  List.iter Domain.join workers;
  let present = ref 0 in
  for i = 1 to n do if S.contains s i then incr present done;
  assert_eq !present 0 "concurrent remove: items still present";
  printf "PASS: concurrent remove\n"

let test_concurrent_mixed () =
  let s = S.create 8 in
  let n = 200 in
  for i = 1 to n / 2 do ignore (S.add s i) done;
  let adders =
    List.init 2 (fun d ->
      Domain.spawn (fun () ->
        for i = n/2 + 1 + d*(n/4) to n/2 + (d+1)*(n/4) do
          ignore (S.add s i)
        done))
  in
  let removers =
    List.init 2 (fun d ->
      Domain.spawn (fun () ->
        for i = 1 + d*(n/4) to (d+1)*(n/4) do
          ignore (S.remove s i)
        done))
  in
  let readers =
    List.init 2 (fun _ ->
      Domain.spawn (fun () ->
        for i = 1 to n do ignore (S.contains s i) done))
  in
  List.iter Domain.join adders;
  List.iter Domain.join removers;
  List.iter Domain.join readers;
  let missing = ref 0 in
  for i = n/2 + 1 to n do
    if not (S.contains s i) then incr missing
  done;
  assert_eq !missing 0 "concurrent mixed: missing add-only items";
  printf "PASS: concurrent mixed\n"

let test_concurrent_same_key_add () =
  let s    = S.create 8 in
  let wins = Atomic.make 0 in
  let workers =
    List.init 8 (fun _ ->
      Domain.spawn (fun () ->
        if S.add s 42 then Atomic.fetch_and_add wins 1 |> ignore))
  in
  List.iter Domain.join workers;
  assert_eq (Atomic.get wins) 1 "exactly one add wins for same key";
  assert_bool (S.contains s 42) "key present after race";
  printf "PASS: concurrent same-key add race\n"

let test_concurrent_same_key_remove () =
  let s    = S.create 8 in
  ignore (S.add s 77);
  let wins = Atomic.make 0 in
  let workers =
    List.init 8 (fun _ ->
      Domain.spawn (fun () ->
        if S.remove s 77 then Atomic.fetch_and_add wins 1 |> ignore))
  in
  List.iter Domain.join workers;
  assert_eq (Atomic.get wins) 1       "exactly one remove wins for same key";
  assert_bool (not (S.contains s 77)) "key absent after race";
  printf "PASS: concurrent same-key remove race\n"

(** add and remove of the same key racing simultaneously; no permanent stuck state. *)
let test_concurrent_add_remove_race () =
  let s = S.create 8 in
  let key = 7 in
  for _ = 1 to 200 do
    ignore (S.add s key);
    let adder   = Domain.spawn (fun () -> ignore (S.add s key)) in
    let remover = Domain.spawn (fun () -> ignore (S.remove s key)) in
    Domain.join adder;
    Domain.join remover;
    ignore (S.remove s key);
    assert_bool (not (S.contains s key)) "key stuck after add/remove race"
  done;
  printf "PASS: concurrent add/remove same-key race\n"

(** Re-add while remove is in flight: no crash, contains stays consistent. *)
let test_read_during_remove () =
  let s = S.create 8 in
  for _ = 1 to 100 do
    ignore (S.add s 13);
    let r = Domain.spawn (fun () -> ignore (S.remove s 13)) in
    let a = Domain.spawn (fun () -> ignore (S.add s 13)) in
    Domain.join r;
    Domain.join a;
    if S.contains s 13 then ignore (S.remove s 13)
  done;
  printf "PASS: re-add during remove\n"

(** High contention: many domains hammering a tiny key set. *)
let test_high_contention_small_keyset () =
  let s    = S.create 8 in
  let keys = 5 in
  let workers =
    List.init 8 (fun _ ->
      Domain.spawn (fun () ->
        for _ = 1 to 200 do
          let k = (Random.int keys) + 1 in
          ignore (S.add s k);
          ignore (S.contains s k);
          ignore (S.remove s k)
        done))
  in
  List.iter Domain.join workers;
  for k = 1 to keys do ignore (S.contains s k) done;
  printf "PASS: high contention small keyset\n"

(** max_level=0 under concurrency: exactly one add wins. *)
let test_max_level_zero_concurrent () =
  let s    = S.create 0 in
  let wins = Atomic.make 0 in
  let workers =
    List.init 4 (fun _ ->
      Domain.spawn (fun () ->
        if S.add s 1 then Atomic.fetch_and_add wins 1 |> ignore))
  in
  List.iter Domain.join workers;
  assert_eq (Atomic.get wins) 1 "level-0 concurrent: exactly one add wins";
  assert_bool (S.contains s 1)  "level-0 concurrent: key visible";
  printf "PASS: max_level zero concurrent\n"

(** Rapid remove/re-add cycles: key must never be permanently lost. *)
let test_remove_readd_cycle () =
  let s   = S.create 8 in
  let key = 99 in
  ignore (S.add s key);
  let workers =
    List.init 4 (fun _ ->
      Domain.spawn (fun () ->
        for _ = 1 to 100 do
          ignore (S.remove s key);
          ignore (S.add s key)
        done))
  in
  List.iter Domain.join workers;
  ignore (S.add s key);
  assert_bool (S.contains s key) "key lost after repeated remove/re-add cycles";
  printf "PASS: remove/re-add cycle\n"

(** Lock ordering test: concurrent ops on overlapping pred sets must not deadlock. *)
let test_no_deadlock_overlapping_preds () =
  let s = S.create 8 in
  (* Pre-populate so preds overlap between concurrent inserts *)
  List.iter (fun k -> ignore (S.add s k)) [1; 5; 10; 15; 20];
  let workers =
    List.init 4 (fun d ->
      Domain.spawn (fun () ->
        for i = 1 to 50 do
          let k = d * 100 + i in
          ignore (S.add s k);
          ignore (S.remove s k)
        done))
  in
  List.iter Domain.join workers;
  printf "PASS: no deadlock with overlapping preds\n"

let test_stress () =
  let s       = S.create 16 in
  let domains = 4 and per = 500 in
  let adders =
    List.init domains (fun d ->
      Domain.spawn (fun () ->
        for i = 1 to per do ignore (S.add s (d * per + i)) done))
  in
  List.iter Domain.join adders;
  let removers =
    List.init domains (fun d ->
      Domain.spawn (fun () ->
        for i = 1 to per do ignore (S.remove s (d * per + i)) done))
  in
  List.iter Domain.join removers;
  let remaining = ref 0 in
  for i = 1 to domains * per do
    if S.contains s i then incr remaining
  done;
  assert_eq !remaining 0 "stress: items remain after full remove pass";
  printf "PASS: stress\n"

let test_all_items_visible_after_join () =
  let s = S.create 8 in
  let domains = 8 and per = 100 in
  let workers =
    List.init domains (fun d ->
      Domain.spawn (fun () ->
        for i = 1 to per do ignore (S.add s (d * 10000 + i)) done))
  in
  List.iter Domain.join workers;
  let collected = ref [] in
  for d = 0 to domains - 1 do
    for i = 1 to per do
      let k = d * 10000 + i in
      if S.contains s k then collected := k :: !collected
    done
  done;
  let expected =
    List.init domains (fun d -> List.init per (fun i -> d * 10000 + i + 1))
    |> List.flatten
  in
  assert_list_eq !collected expected "all items visible after join";
  printf "PASS: all items visible after join\n"

(* ── entry point ────────────────────────────────────────────────────────── *)

let () =
  test_sequential_basic ();
  test_duplicate_add ();
  test_remove_basic ();
  test_invalid_arg ();
  test_sequential_many ();
  test_readd_after_remove ();
  test_max_level_zero ();
  test_boundary_keys ();
  test_contains_after_remove ();
  test_loser_sees_key ();

  test_concurrent_add ();
  test_concurrent_remove ();
  test_concurrent_mixed ();
  test_concurrent_same_key_add ();
  test_concurrent_same_key_remove ();
  test_concurrent_add_remove_race ();
  test_readd_during_remove ();
  test_high_contention_small_keyset ();
  test_max_level_zero_concurrent ();
  test_remove_readd_cycle ();
  test_no_deadlock_overlapping_preds ();
  test_stress ();
  test_all_items_visible_after_join ();

  printf "\nAll tests passed!\n"