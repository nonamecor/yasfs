let repeat n v =
  let rec repeat n v r =
    if n=0 then r else repeat (n-1) v (v::r) in
  repeat n v []

let rec compile exp code = match exp with
    Lambda.Int v -> (Instruct.Const v)::code
  | Lambda.Bool v -> (Instruct.Bool v)::code
  | Lambda.Tuple vs -> let n = (List.length vs) in
    (List.flatten (List.map (fun x -> compile x []) vs)) @ (Instruct.MakeTuple n)::code
  | Lambda.Union (tag, e) -> (compile e []) @ (Instruct.MakeUnion tag)::code
  | Lambda.Var n -> (Instruct.Access n)::code
  | Lambda.Bind t -> compile t (Instruct.Bind::code)
  | Lambda.Fun (n,ts) ->
    let body = Instruct.Pop::(repeat n Instruct.Grab) @ (compile_body ts) in
        (Instruct.Closure body)::code
  | Lambda.Fun1 (n,ts) ->
    let body = (repeat n Instruct.Grab) @ (compile_body ts) in
        (Instruct.Closure body)::code
  | Lambda.App (t,ts) ->
    let init = compile t (Instruct.Apply::code) in
    Instruct.Pushmark::(List.fold_left (fun a b -> compile b a) init ts)
  | Lambda.If (t, succ, fail) ->
    compile t [Instruct.Branch ((compile succ code), (compile fail code))]
  | Lambda.Switch (t, cases) ->
    let rec handle cases code =
      match cases with
      | [] -> code
      | (ith, case)::xs ->
      [Instruct.Copy; (Instruct.Const ith); Instruct.Equal;
       (Instruct.Branch ((compile case code), (handle xs code)))] in
    compile t (handle cases code)
  | Lambda.Prim s -> (Instruct.Prim s)::code
  | Lambda.Plus (a, b) ->
    compile a (compile b (Instruct.Plus::code))
  | Lambda.Sub (a, b) ->
    compile a (compile b (Instruct.Sub::code))
  | Lambda.Mul (a, b) ->
    compile a (compile b (Instruct.Mul::code))
  | Lambda.Equal (a, b) ->
    compile a (compile b (Instruct.Equal::code))
and compile_tail exp = match exp with
    Lambda.Int v -> [Instruct.Const v]
  | Lambda.Bool v -> [Instruct.Bool v]
  | Lambda.Prim s -> [Instruct.Prim s]
  | Lambda.Tuple vs -> let n = (List.length vs) in
    (List.flatten (List.map (fun x -> compile x []) vs)) @
    [Instruct.MakeTuple n; Instruct.Return]
  | Lambda.Union (tag, e) -> (compile e []) @
    [Instruct.MakeTuple tag; Instruct.Return]
  | Lambda.Var n -> [Instruct.Access n; Instruct.Return]
  | Lambda.Bind t -> [Instruct.Bind]
  | Lambda.Switch _ -> compile exp [Instruct.Return]
  | Lambda.Plus _ -> compile exp [Instruct.Return]
  | Lambda.Sub _ -> compile exp [Instruct.Return]
  | Lambda.Mul _ -> compile exp [Instruct.Return]
  | Lambda.Equal _ -> compile exp [Instruct.Return]
  | Lambda.If _ -> compile exp [Instruct.Return]
  | Lambda.Fun (n,ts) -> (match ts with
    | [t] -> (match n with
        | 0 -> compile_tail t
        | _ -> Instruct.Pop::Instruct.Grab::(compile_tail (Lambda.Fun (n-1,[t]))))
    | _ -> failwith "must be one")
  | Lambda.Fun1 (n,ts) -> (match ts with
    | [t] -> (match n with
        | 0 -> compile_tail t
        | _ -> Instruct.Grab::(compile_tail (Lambda.Fun (n-1,[t]))))
    | _ -> failwith "must be one")
  | Lambda.App (t,ts) ->
    (t::ts
     |> List.rev
     |> List.map (fun x -> compile x [])
     |> List.flatten) @ [Instruct.Tailapply]
and compile_body ts = match ts with
  | [x] -> compile_tail x
  | x::xs -> compile x (compile_body xs)
  | [] -> []

type result =
    Value of int
  | Bool of bool
  | Tuple of result list
  | Union of int * result
  | Prim of string
  | Lambda of (Instruct.t list * result list)
  | Eplison

let env_get (e : result list) n = List.nth e n

let env_put (e : result list) v = v :: e

let step (c, e, s, r) op =
  match op with
  Instruct.Bool v -> Stack.push (Bool v) s; (c, e, s, r)
  | Instruct.Const v -> Stack.push (Value v) s; (c, e, s, r)
  | Instruct.Prim str -> Stack.push (Prim str) s; (c, e, s, r)
  | Instruct.MakeTuple n ->
    let rec loop i n res =
      if i=n then begin Stack.push (Tuple res) s; (c, e, s, r) end
      else loop (i+1) n ((Stack.pop s)::res)
    in loop 0 n []
  | Instruct.MakeUnion tag ->
    Stack.push (Union (tag, (Stack.pop s))) s; (c, e, s, r)
  | Instruct.Pop -> Stack.pop s |> ignore; (c, e, s, r)
  | Instruct.Copy -> Stack.push (Stack.top s) s |> ignore; (c, e, s, r)
  | Instruct.Plus -> (match Stack.pop s with
    | Value x -> (match Stack.pop s with
        | Value y -> Stack.push (Value (x+y)) s;
          (c, e, s, r)
        | _ -> failwith "can add non int")
    | _ -> failwith "can add non int")
  | Instruct.Sub -> (match Stack.pop s with
    | Value x -> (match Stack.pop s with
        | Value y -> Stack.push (Value (y-x)) s;
          (c, e, s, r)
        | _ -> failwith "can add non int")
    | _ -> failwith "can add non int")
  | Instruct.Mul -> (match Stack.pop s with
    | Value x -> (match Stack.pop s with
        | Value y -> Stack.push (Value (x*y)) s;
          (c, e, s, r)
        | _ -> failwith "can add non int")
    | _ -> failwith "can add non int")
  | Instruct.Equal -> (match Stack.pop s with
    | Value x -> (match Stack.pop s with
        | Value y -> Stack.push (Bool (if x=y then true else false)) s;
          (c, e, s, r)
        | _ -> failwith "can add non int")
    | _ -> failwith "can add non int")
  | Instruct.Branch (succ, fail) ->
    (match Stack.pop s with
     | Bool x -> if x then
         (succ, e, s, r)
       else (fail, e, s, r)
     | _ -> failwith "branch instruct expect bool type")
  | Instruct.Access n -> Stack.push (env_get e n) s; (c, e, s, r)
  | Instruct.Closure c1 -> Stack.push (Lambda (c1,e)) s; (c, e, s, r)
  | Instruct.Tailapply ->
    let (c1,e1) = match Stack.top s with
        Lambda x -> x
      | _ -> failwith "cannot tailapply with non closure" in
    (c1, e1, s, r)
  | Instruct.Apply ->
    (match Stack.top s with
     | Lambda (c1, e1) ->
       Stack.push (Lambda (c,e)) r;
       (c1, e1, s, r)
     | Prim str -> if str = "tag" then
         (Stack.pop s |> ignore;
         match Stack.top s with
          | Union (tag, res) -> Stack.push (Value tag) s; (c, e, s, r)
          | _ -> assert false)
       else assert false
     | _ -> failwith "cannot apply non closure")
  | Instruct.Pushmark -> Stack.push Eplison s; (c, e, s, r)
  | Instruct.Grab ->
    if Stack.top s = Eplison then
      (Stack.pop s |> ignore;
       Stack.push (Lambda (Instruct.Grab::c,e)) s;
       (let (c1,e1) = match Stack.pop r with
             Lambda x -> x
           | _ -> failwith "should be closure in r" in
        (c1, e1, s, r)))
    else let v = Stack.pop s in
      (c, (env_put e v), s, r)
  | Instruct.Return ->
    let v = Stack.pop s in
    (if Stack.top s = Eplison then
      (Stack.pop s |> ignore; Stack.push v s;
       let (c1,e1) = match Stack.pop r with
           Lambda x -> x
         | _ -> failwith "should be closure in return" in
       (c1, e1, s, r))
    else match v with
        Lambda (c1,e1) -> (c1, e1, s, r)
      | _ -> failwith "should be")
  | _ -> failwith "not implement"

let run code e s r =
  let rec loop (c, e, s, r) =
    match c with
    | [] -> failwith "must stop with Instruct.Stop"
    | [Instruct.Stop] -> Stack.top s
    | op::c1 -> loop (step (c1, e, s, r) op)
  in loop (code, e, s, r)
