(* Benchmark to compare lock-free skiplist, fine-grain skiplist 
  and course-grain hashtabl implementation

  Measures throughput (ops/sec) for above implementations
  under various workload ratios (contains/add/remove mix) and thread counts *)

module type SKIPLIST = sig
  type t
  val create: int -> t
  val add: t -> int -> bool
  val remove: t -> int -> bool
  val contains: t -> int -> bool
end

(* Atomic counter for total operations *)
let total_ops = Atomic.make 0

let benchmark_list
    (module SL : SKIPLIST)
    ~num_threads
    ~duration_sec
    ~contains_pct
    ~max_level
    ~initial_size
    ~value_range =

  (* Create and populate list *)
  let list = SL.create max_level in
  let rng = Random.State.make [|42|] in
  for _ = 1 to initial_size do
    let _ = SL.add list (Random.State.int rng value_range) in
    ()
  done;

  (* Reset counter *)
  Atomic.set total_ops 0;
  let stop = Atomic.make false in

  (* Worker thread function *)
  let worker () =
    let local_rng = Random.State.make_self_init () in
    let local_ops = ref 0 in

    while not (Atomic.get stop) do
      let op_type = Random.State.int local_rng 100 in
      let value = Random.State.int local_rng value_range in

      (if op_type < contains_pct then
        SL.contains list value
      else if op_type < contains_pct + ((100 - contains_pct) / 2) then
        SL.add list value
      else
        SL.remove list value) |> ignore;

      incr local_ops
    done;

    Atomic.fetch_and_add total_ops !local_ops |> ignore
  in

  (* Start worker domains *)
  let start_time = Unix.gettimeofday () in
  let domains = List.init num_threads (fun _ -> Domain.spawn worker) in

  (* Run for specified duration *)
  Unix.sleepf duration_sec;
  Atomic.set stop true;

  (* Wait for all domains to finish *)
  List.iter Domain.join domains;
  let end_time = Unix.gettimeofday () in

  let elapsed = end_time -. start_time in
  let ops = Atomic.get total_ops in
  let throughput = float_of_int ops /. elapsed in

  (ops, elapsed, throughput)

(* Main benchmark runner *)
let run_benchmark impl_name num_threads contains_pct duration max_level initial_size value_range runs =
  let module_of_name = function
    | "lockfree" -> (module Lockfree_skiplist : SKIPLIST)
    | "finegrain" -> (module Finegrain_skiplist : SKIPLIST)
    | "hashtbl" -> (module Coarsegrain_hashtbl : SKIPLIST)
    | _ -> failwith "Unknown implementation"
  in

  let impl_module = module_of_name impl_name in
  let results = ref [] in

  Printf.printf "Running %s with %d threads, %d%% contains...\n%!"
    impl_name num_threads contains_pct;

  for run = 1 to runs do
    Printf.printf "  Run %d/%d... %!" run runs;
    (* Compact heap between runs for consistent memory state *)
    if run > 1 then Gc.compact ();
    let (ops, elapsed, throughput) =
      benchmark_list impl_module ~num_threads ~duration_sec:duration
        ~contains_pct ~max_level ~initial_size ~value_range
    in
    Printf.printf "%d ops in %.2fs (%.0f ops/sec)\n%!" ops elapsed throughput;
    results := throughput :: !results
  done;

  (* Calculate statistics *)
  let sorted = List.sort compare !results in
  let median = List.nth sorted (List.length sorted / 2) in
  let avg = (List.fold_left (+.) 0.0 !results) /. float_of_int (List.length !results) in

  Printf.printf "  Median: %.0f ops/sec, Avg: %.0f ops/sec\n\n%!" median avg;
  (median, avg)

let () =
  let impl = ref "lockfree" in
  let threads = ref 4 in
  let contains = ref 90 in
  let duration = ref 2.0 in
  let initial_size = ref 1000 in
  let max_level = ref 10 in
  let value_range = ref 10000 in
  let runs = ref 3 in
  let csv_output = ref None in

  let speclist = [
    ("--impl", Arg.Set_string impl,
     "Implementation: lockfree, finegrain (default: lockfree)");
    ("--threads", Arg.Set_int threads,
     "Number of threads (default: 4)");
    ("--contains", Arg.Set_int contains,
     "Percentage of contains operations (default: 90)");
    ("--duration", Arg.Set_float duration,
     "Duration in seconds (default: 2.0)");
    ("--initial-size", Arg.Set_int initial_size,
     "Initial list size (default: 1000)");
    ("--max-level", Arg.Set_int max_level,
     "Max levels in the skip list (default: 10)");
    ("--value-range", Arg.Set_int value_range,
     "Range of values [0, N) (default: 10000)");
    ("--runs", Arg.Set_int runs,
     "Number of runs (default: 3)");
    ("--csv", Arg.String (fun s -> csv_output := Some s),
     "Output CSV file (optional)");
  ] in

  Arg.parse speclist (fun _ -> ())
    "Benchmark concurrent skiplist implementations";

  Printf.printf "=== SkipList Benchmark ===\n";
  Printf.printf "Implementation: %s\n" !impl;
  Printf.printf "Threads: %d\n" !threads;
  Printf.printf "Workload: %d%% contains, %d%% add, %d%% remove\n"
    !contains ((100 - !contains)/2) ((100 - !contains)/2);
  Printf.printf "Duration: %.1fs per run\n" !duration;
  Printf.printf "Initial size: %d items\n" !initial_size;
  Printf.printf "Max levels: %d\n" !max_level;
  Printf.printf "Value range: [0, %d)\n" !value_range;
  Printf.printf "Runs: %d\n\n%!" !runs;

  let (median, avg) = run_benchmark !impl !threads !contains !duration
    !max_level !initial_size !value_range !runs in

  (* Output CSV if requested *)
  begin match !csv_output with
  | Some filename ->
      let oc = open_out_gen [Open_append; Open_creat] 0o644 filename in
      Printf.fprintf oc "%s,%d,%d,%d,%.0f,%.0f\n" !impl !threads !max_level !contains median avg;
      close_out oc;
      Printf.printf "Results appended to %s\n%!" filename
  | None -> ()
  end
