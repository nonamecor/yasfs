let idSTOP    = 1
let idPUSHADDR = 2
let idCONST   = 3
let idPUSH    = 4
let idCLOSURE = 5
let idAPPLY   = 6
let idGRAB    = 7
let idRESTART  = 8
let idSTACKACC = 9
let idENVACC  = 10
let idADDINT  = 11
let idRETURN  = 12
let idBRANCH  = 13
let idBRANCHIF = 14
let idEQ      = 15
let idSUBINT  = 16
let idMULINT  = 17
let idDIVINT  = 18
let idMAKEBLOCK = 19
let idGETFIELD = 20
let idSWITCH  = 21
let idCCALL   = 22
let idSTRING   = 23


type buffer = {mutable data: bytes; mutable pos: int};;

let buffer_append b1 b2 =
  let len = Bytes.length b1.data in
  (if b1.pos + b2.pos > len then
     let newbuf = Bytes.create ((len*2)+b2.pos) in
     Bytes.blit b1.data 0 newbuf 0 b1.pos;
     Bytes.blit b2.data 0 newbuf b1.pos b2.pos;
     b1.data <- newbuf;
   else
     Bytes.blit b2.data 0 b1.data b1.pos b2.pos);
  b1.pos <- b1.pos + b2.pos

let new_buffer () = {data = Bytes.create 32; pos = 0}

let o_byte b c =
  let len = Bytes.length b.data in
  if b.pos >= len then (
    let newbuf = Bytes.create (len*2) in
    Bytes.blit b.data 0 newbuf 0 len;
    b.data <- newbuf
  );
  Bytes.set b.data b.pos c;
  b.pos <- b.pos + 1

let o_uint32 b u =
  let p0 = u land 255 |> char_of_int in
  let p1 = u lsr 8 land 255 |> char_of_int in
  let p3 = u lsr 16 land 255 |> char_of_int in
  let p4 = u lsr 24 land 255 |> char_of_int in
  o_byte b p0; o_byte b p1; o_byte b p3; o_byte b p4

let o_uint64 b u =
  let u1 = u land 4294967295 in
  let u2 = u lsr 32 land 4294967295 in
  o_uint32 b u1; o_uint32 b u2

let o b id =
  o_byte b (id land 255 |> char_of_int)


let rec fnbuf = function
  | [] -> 0
  | buf::[] -> buf.pos
  | x::xs ->
    let ofst = fnbuf xs in
    o x idBRANCH;
    o_uint32 x ofst;
    ofst+x.pos

let rec emit_inst buf x =
  match x with
  | Instruct.Const n -> o buf idCONST;o_uint64 buf (n*2+1)
  | Instruct.Bool n -> o buf idCONST;
    o_uint64 buf (if n then 18 else 34)
  | Instruct.Stop -> o buf idSTOP
  | Instruct.Apply -> o buf idAPPLY
  | Instruct.Plus -> o buf idADDINT
  | Instruct.Sub -> o buf idSUBINT
  | Instruct.Mul -> o buf idMULINT
  | Instruct.Div -> o buf idDIVINT
  | Instruct.Return ->
    o buf idRETURN;
  | Instruct.Closure l ->
    let tmpbuf = new_buffer () in
    List.iter (emit_inst tmpbuf) l;
    o buf idCLOSURE;
    o_uint32 buf tmpbuf.pos;
    buffer_append buf tmpbuf
  | Instruct.Grab n ->
    o buf idRESTART;
    o buf idGRAB;
    o_byte buf (char_of_int n);
  | Instruct.PushRetAddr l ->
    let tmpbuf = new_buffer () in
    List.iter (emit_inst tmpbuf) l;
    o buf idPUSHADDR;
    o_uint32 buf tmpbuf.pos;
    buffer_append buf tmpbuf
  | Instruct.Push ->
    o buf idPUSH
  | Instruct.StackAccess n ->
    o buf idSTACKACC;
    o_byte buf (char_of_int n)
  | Instruct.EnvAccess n ->
    o buf idENVACC;
    o_byte buf (char_of_int n)
  | Instruct.Branch (t,f) ->
    let truebuf = new_buffer () in
    let falsebuf = new_buffer () in
    List.iter (emit_inst truebuf) t;
    List.iter (emit_inst falsebuf) f;
    o buf idBRANCHIF;
    o_uint32 buf (falsebuf.pos+5);
    buffer_append buf falsebuf;
    o buf idBRANCH;
    o_uint32 buf truebuf.pos;
    buffer_append buf truebuf
  | Instruct.Equal -> o buf idEQ
  | Instruct.MakeTuple (tag, size) ->
    o buf idMAKEBLOCK;
    o_uint32 buf tag;
    o_uint32 buf size
  | Instruct.Field i ->
    o buf idGETFIELD;
    o_uint32 buf i
  | Instruct.Switch l ->
    let emits = function ls ->
      let buf = new_buffer() in
      List.iter (emit_inst buf) ls;
      buf
    in
    let ii = List.map (fun (i,_) -> i) l in
    let tt = List.map (fun (_,t) -> t) l in
    let ll = List.map emits tt in
    fnbuf ll;
    o buf idSWITCH;
    o_uint32 buf (List.length ll);
    List.iter2 (fun i v ->
        o_uint32 buf i;
        o_uint32 buf v.pos) ii ll;
    List.iter (buffer_append buf) ll
  | Instruct.String s ->
    let n = String.length s in
    o buf idSTRING;
    o_uint32 buf n;
    buffer_append buf {data=(Bytes.of_string s); pos=n};
    o_byte buf (char_of_int 0)
  | Instruct.Prim (str,n) ->
    o buf idCCALL;
    o_uint32 buf n
let emit buf bc =
  List.iter (emit_inst buf) bc;
  Bytes.sub buf.data 0 buf.pos
