(* File lexerTypes.mll *)
{
open Parser        (* The type token is defined in parser.mli *)
exception Eof
open Lexing 

let incrline lexbuf =
    lexbuf.lex_curr_p <- {
    lexbuf.lex_curr_p with
    pos_bol = lexbuf.lex_curr_p.pos_cnum;
    pos_lnum = 1 + lexbuf.lex_curr_p.pos_lnum }
}
let nameString = ['a' - 'z']+ ['a' - 'z' 'A' - 'Z' '0' - '9' '_']* (* types and terms start with lower case letters *)
let commentString = ['%'] [^'\n']* '\n' (* comments start with % *)
let instring = [^'"'] *
let subexp = ['a' - 'z'] ['a' - 'z' 'A' - 'Z' '0' - '9' '_']* (* subexponentials start with a lower case letter and can have numbers *)
let varName = ['A' - 'Z'] ['a' - 'z' 'A' - 'Z' '0' - '9' '_']*
let subtype =  "lin"  |  "aff" | "rel" | "unb"

rule token = parse 

[' ' '\t' '\r']         { token lexbuf }
| commentString         { incrline lexbuf; token lexbuf }
| '\n'                  { incrline lexbuf; token lexbuf }
| "kind"                { KIND }
| "type"                { TYPE }
| "tsub"                {TSUBEX}
| "subexp"              { SUBEX }
| "context"       {CONTEXT}      
| "subexprel"          {SUBEXPREL}
| subtype as tsub {TSUB(tsub)}
| ':'                   { DOTS }
| "->"                  { TARR }
| '.'                   { DOT }
| "int"                 { TINT }
| "list"                { TLIST }
| "string"              { TSTRING }
| '('                   { LPAREN }
| ')'                   { RPAREN }
| '"' (instring as n) '"'
                        { String.iter (function '\n' -> incrline lexbuf | _ -> ()) n ;
                              STRING n }
| eof                   { raise Eof }
| "print"             {PRINT}
| "is"                  {IS}
| '+'                   { PLUS }
| '-'                   { MINUS }
| '*'                   { TIMES }
| '/'                   { DIV } 
| "<>"                   { NEQ }  
| "<"                   { LESS }
| "<="                  { LEQ }
| '>'                   { GRT }
| ">="                  { GEQ }
| '='                   { EQ }          
| ":="                  { DEF }
| ":-"                  { INVLOLLI } 
| "-o"                { LOLLI }
| ','                   { COMMA }
| "top"                 { TOP }
| "one"                 { ONE }
| "pi \\" (varName as lxm)        { FORALL(lxm) }     
| "hbang"               { HBANG }
| "bang"                { BANG }
| nameString as lex     { NAME(lex) }
| "!"                   { CUT }
| '&'                   { WITH }
| '['                   { LBRACKET }
| ']'                   { RBRACKET }
| '{'			{ LCURLY }
| '}'			{ RCURLY }
| varName as lxm    { VAR(lxm) }
| ['0'-'9']+ as lxm     { INT(int_of_string lxm) }
| '\\' (varName as lxm) { ABS(lxm) }
| "nsub \\" (varName as lxm)        { NEW(lxm) } 
