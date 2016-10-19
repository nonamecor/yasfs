open Driver
open Zinc

let test_identity () =
  (eval "(fn x -> x) 5") = (Value 5)

let test_multi_argument () =
  (eval "(fn x y -> y) 2 42") = (Value 42)

let test_partial_apply () =
  (eval "((fn x y -> y) 1) 42") = (Value 42)

let test_variable_bind () =
  (eval "a := 3; a") = (Value 3)

let test_sum100 () =
  (eval "(fn loop i sum =>
            if i=101 then sum
            else (loop (i+1) (sum+i)))
          1 0") = (Value 5050)

let test_factorial () =
  (eval "(fn fact n =>
          if n=0 then 1
          else n * fact (n-1)) 5") = (Value 120)

let test_plus () =
  (eval "1+2") = (Value 3)

let test_plus1 () =
  (eval "(fn x y -> x + y) 3 5") = (Value 8)

let test_mul () =
  (eval "3*7") = (Value 21)

let test_bool () =
  ((eval "1=1") = (Bool true)) && ((eval "1=2") = (Bool false))

let test_if_then_else () =
  (eval "if 1=1 then 5 else 2") = (Value 5)

let test_closure () =
  (eval "(fn x -> (fn y -> x+y)) 1 2") = (Value 3)

let tests = [
  ("identity", test_identity);
  ("multi_argument", test_multi_argument);
  ("partial_apply", test_partial_apply);
  ("variable_bind", test_variable_bind);
  ("test_plus", test_plus);
  ("test_mul", test_mul);
  ("test_plus1", test_plus1);
  ("test_if_then_else", test_if_then_else);
  ("test_sum100", test_sum100);
  ("factorial", test_factorial);
  ("test_closure", test_closure);
]


let testfn = function (a, b) -> Printf.printf "%s ... %s\n" a (if b () then "ok" else "fail");;

List.iter testfn tests
