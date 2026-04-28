(* Benchmark to compare lock-free skiplist, fine-grain skiplist implementation

  Measures avg traversal lengths for above implementations
  under various workload ratios (contains/add/remove mix) and thread counts *)

module type SKIPLIST = sig
  type t
  val create: int -> t
  val add: t -> int -> bool * int
  val remove: t -> int -> bool * int
  val contains: t -> int -> bool * int
end

(* Atomic counters for total operations *)
let total_contains_count = Atomic.make 0
let total_contains_sum = Atomic.make 0
let total_add_sum = Atomic.make 0
let total_add_count = Atomic.make 0
let total_remove_count = Atomic.make 0
let total_remove_sum = Atomic.make 0

let benchmark_list
    (module SL : SKIPLIST)
    ~num_threads
    ~runs
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

  Atomic.set total_contains_count 0;
  Atomic.set total_contains_sum 0;
  Atomic.set total_remove_sum 0;
  Atomic.set total_remove_count 0;
  Atomic.set total_add_count 0;
  Atomic.set total_add_sum 0;

  (* Worker thread function *)
  let worker () =
    let local_rng = Random.State.make_self_init () in
    let cur_runs = ref 0 in
    let contains_count = ref 0 in
    let contains_sum = ref 0 in
    let add_sum = ref 0 in
    let add_count = ref 0 in
    let remove_count = ref 0 in
    let remove_sum = ref 0 in

    while !cur_runs < runs do
      let op_type = Random.State.int local_rng 100 in
      let value = Random.State.int local_rng value_range in
      
      (if op_type < contains_pct then
        let (_, count) = SL.contains list value in
        incr contains_count;
        contains_sum := !contains_sum + count 
      else if op_type < contains_pct + ((100 - contains_pct) / 2) then
        let (_, count) = SL.add list value in
        incr add_count;
        add_sum := !add_sum + count
      else
        let (_, count) = SL.remove list value in
        remove_sum := !remove_sum + count;
        incr remove_count);

      incr cur_runs
    done;

    Atomic.fetch_and_add total_contains_count !contains_count |> ignore;
    Atomic.fetch_and_add total_contains_sum !contains_sum |> ignore;
    Atomic.fetch_and_add total_add_count !add_count |> ignore;
    Atomic.fetch_and_add total_add_sum !add_sum |> ignore;
    Atomic.fetch_and_add total_remove_sum !remove_sum |> ignore;
    Atomic.fetch_and_add total_remove_count !remove_count |> ignore;
  in

  let domains = List.init num_threads (fun _ -> Domain.spawn worker) in

  (* Wait for all domains to finish *)
  List.iter Domain.join domains;
  ()

(* Main benchmark runner *)
let run_benchmark impl_name num_threads contains_pct max_level initial_size value_range runs =
  let module_of_name = function
    | "lockfree" -> (module Lockfree_skiplist_with_stats : SKIPLIST)
    | "finegrain" -> (module Finegrain_skiplist_with_stats : SKIPLIST)
    | _ -> failwith "Unknown implementation"
  in

  let impl_module = module_of_name impl_name in

  Printf.printf "Running %s with %d threads, %d%% contains...\n%!"
    impl_name num_threads contains_pct;

  benchmark_list impl_module ~num_threads ~runs ~contains_pct ~initial_size ~value_range ~max_level;

  (* Calculate statistics *)
  let safe_avg sum count =
    if count = 0 then 0.0
    else float_of_int sum /. float_of_int count in
  let avg_contains_length = safe_avg (Atomic.get total_contains_sum) (Atomic.get total_contains_count) in
  let avg_add_length = safe_avg (Atomic.get total_add_sum) (Atomic.get total_add_count) in
  let avg_remove_length = safe_avg (Atomic.get total_remove_sum) (Atomic.get total_remove_count) in

  Printf.printf "Avg Contains traversal length: %.0f \n%!" avg_contains_length;
  Printf.printf "Avg Add traversal length: %.0f \n%!" avg_add_length;
  Printf.printf "Avg Remove traversal length: %.0f \n%!" avg_remove_length;

  (avg_contains_length, avg_add_length, avg_remove_length)

let () =
  let impl = ref "lockfree" in
  let threads = ref 4 in
  let contains = ref 90 in
  let initial_size = ref 1000 in
  let max_level = ref 10 in
  let value_range = ref 10000 in
  let runs = ref 1000 in
  let csv_output = ref None in

  let speclist = [
    ("--impl", Arg.Set_string impl,
     "Implementation: lockfree, finegrain (default: lockfree)");
    ("--threads", Arg.Set_int threads,
     "Number of threads (default: 4)");
    ("--contains", Arg.Set_int contains,
     "Percentage of contains operations (default: 90)");
    ("--initial-size", Arg.Set_int initial_size,
     "Initial list size (default: 1000)");
    ("--max-level", Arg.Set_int max_level,
     "Max levels in the skip list (default: 10)");
    ("--value-range", Arg.Set_int value_range,
     "Range of values [0, N) (default: 10000)");
    ("--runs", Arg.Set_int runs,
     "Number of runs (default: 1000)");
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
  Printf.printf "Initial size: %d items\n" !initial_size;
  Printf.printf "Max levels: %d\n" !max_level;
  Printf.printf "Value range: [0, %d)\n" !value_range;
  Printf.printf "Runs: %d\n\n%!" !runs;

  let (avg_contains_length, avg_add_length, avg_remove_length) = run_benchmark !impl !threads !contains
    !max_level !initial_size !value_range !runs in

  (* Output CSV if requested *)
  begin match !csv_output with
  | Some filename ->
      let oc = open_out_gen [Open_append; Open_creat] 0o644 filename in
      Printf.fprintf oc "%s,%d,%d,%d,%.0f,%.0f,%.0f\n" !impl !threads !max_level !contains avg_contains_length avg_add_length avg_remove_length;
      close_out oc;
      Printf.printf "Results appended to %s\n%!" filename
  | None -> ()
  end
