(** QCheck-STM State Machine Test for Lock-Free Skip List

    == Expected Result ==
    This test should PASS.
*)

open QCheck
open STM

module LFS = Lockfree_skiplist

type cmd =
  | Add      of int
  | Remove   of int
  | Contains of int

let show_cmd = function
  | Add k      -> Printf.sprintf "Add(%d)" k
  | Remove k   -> Printf.sprintf "Remove(%d)" k
  | Contains k -> Printf.sprintf "Contains(%d)" k

let arb_cmd _state =
  QCheck.make ~print:show_cmd
    (Gen.oneof
      [ Gen.map (fun k -> Add k)      (Gen.int_range 0 20)
      ; Gen.map (fun k -> Remove k)   (Gen.int_range 0 20)
      ; Gen.map (fun k -> Contains k) (Gen.int_range 0 20)
      ])

let next_state cmd state =
  match cmd with
  | Add k ->
    if List.mem k state then state
    else List.sort compare (k :: state)
  | Remove k ->
    List.filter (fun x -> x <> k) state
  | Contains _ ->
    state

let precond _cmd _state = true

let run cmd sut =
  match cmd with
  | Add k      -> Res (bool, LFS.add      sut k)
  | Remove k   -> Res (bool, LFS.remove   sut k)
  | Contains k -> Res (bool, LFS.contains sut k)

let postcond cmd state result =
  match cmd, result with
  | Add k,      Res ((Bool, _), actual) ->
    actual = not (List.mem k state)
  | Remove k,   Res ((Bool, _), actual) ->
    actual = List.mem k state
  | Contains k, Res ((Bool, _), actual) ->
    actual = List.mem k state
  | _ -> false

module Spec = struct
  type sut   = LFS.t
  type state = int list
  type nonrec cmd = cmd

  let arb_cmd    = arb_cmd
  let show_cmd   = show_cmd
  let init_state = []
  let next_state = next_state
  let precond    = precond
  let run        = run
  let init_sut () = LFS.create 8
  let cleanup _   = ()
  let postcond   = postcond
end

module Seq = STM_sequential.Make(Spec)
module Dom = STM_domain.Make(Spec)

let () =
  QCheck_base_runner.run_tests_main
    [ Seq.agree_test     ~count:1000 ~name:"LF skiplist STM sequential"
    ; Dom.agree_test_par ~count:1000 ~name:"LF skiplist STM parallel (domain)"
    ]