(** QCheck-STM State Machine Test for Fine-Grained Locking Skip List

    == Expected Result ==
    This test should PASS.
*)

open QCheck
open STM

module FGS = Finegrain_skiplist

(* ------------------------------------------------------------------ *)
(*  Commands                                                            *)
(* ------------------------------------------------------------------ *)

type cmd =
  | Add      of int
  | Remove   of int
  | Contains of int

let show_cmd = function
  | Add k      -> Printf.sprintf "Add(%d)" k
  | Remove k   -> Printf.sprintf "Remove(%d)" k
  | Contains k -> Printf.sprintf "Contains(%d)" k

(* Small key range so concurrent ops collide often *)
let arb_cmd _state =
  QCheck.make ~print:show_cmd
    (Gen.oneof
      [ Gen.map (fun k -> Add k)      (Gen.int_range 0 20)
      ; Gen.map (fun k -> Remove k)   (Gen.int_range 0 20)
      ; Gen.map (fun k -> Contains k) (Gen.int_range 0 20)
      ])

(* ------------------------------------------------------------------ *)
(*  Sequential model — just a sorted int list                          *)
(* ------------------------------------------------------------------ *)

let next_state cmd state =
  match cmd with
  | Add k ->
    if List.mem k state then state
    else List.sort compare (k :: state)
  | Remove k ->
    List.filter (fun x -> x <> k) state
  | Contains _ ->
    state   (* read-only *)

let precond _cmd _state = true

(* ------------------------------------------------------------------ *)
(*  Run on real SUT                                                     *)
(* ------------------------------------------------------------------ *)

let run cmd sut =
  match cmd with
  | Add k      -> Res (bool, FGS.add      sut k)
  | Remove k   -> Res (bool, FGS.remove   sut k)
  | Contains k -> Res (bool, FGS.contains sut k)

(* ------------------------------------------------------------------ *)
(*  Postcondition — check real result against model prediction         *)
(* ------------------------------------------------------------------ *)

let postcond cmd state result =
  match cmd, result with
  | Add k,      Res ((Bool, _), actual) ->
    (* add returns true iff key was NOT already in the set *)
    actual = not (List.mem k state)
  | Remove k,   Res ((Bool, _), actual) ->
    (* remove returns true iff key WAS in the set *)
    actual = List.mem k state
  | Contains k, Res ((Bool, _), actual) ->
    (* contains returns true iff key is in the set *)
    actual = List.mem k state
  | _ -> false

(* ------------------------------------------------------------------ *)
(*  Spec module                                                         *)
(* ------------------------------------------------------------------ *)

module Spec = struct
  type sut   = FGS.t
  type state = int list
  type nonrec cmd = cmd

  let arb_cmd   = arb_cmd
  let show_cmd  = show_cmd
  let init_state = []
  let next_state = next_state
  let precond    = precond
  let run        = run
  let init_sut () = FGS.create 8
  let cleanup _   = ()
  let postcond   = postcond
end

module Seq = STM_sequential.Make(Spec)
module Dom = STM_domain.Make(Spec)

let () =
  QCheck_base_runner.run_tests_main
    [ Seq.agree_test     ~count:1000 ~name:"FG skiplist STM sequential"
    ; Dom.agree_test_par ~count:1000 ~name:"FG skiplist STM parallel (domain)"
    ]