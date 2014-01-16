/* 
 * Parser for models generated by DLV
 *
 * Giselle Machado Reis 
 * 2013
 *
 * NOTE: not checking whether the symbols exist or not
 */

%{
  
(* Header (OCaml code) *)

open Term
open TypeChecker

let parse_error s = 
  print_endline s;
  flush stdout

let make_APP lst = 
  match lst with
  | [t] -> t
  | t1 :: body -> APP(t1, body)
  | [] -> failwith "Cannot make application with empty list."

%}

/* OCamlyacc declarations (names of terminal and non-terminal symbols, operator
   precedence, etc.)
*/

/* Terminal symbols */
%token <int> INDEX
%token <string> NAME STRING FORALL EXISTS VAR ABS NEW
%token IN ELIN EMP UNION REQIN
%token LOLLI TIMES PLUS PIPE WITH TOP BOT ONE ZERO HBANG BANG QST NOT
%token COMMA LBRACKET RBRACKET LCURLY RCURLY LPAREN RPAREN UNDERSCORE DOT NEWLINE QUOTE
%right FORALL EXISTS
%left TIMES
%left PLUS
%left PIPE
%left WITH 
%left LOLLI
%right NOT NEW
%right QST BANG HBANG

/* Start symbol */
%start model
%type <Constraints.constraintpred list> model

/* Using this a start symbol will only parse and not return a model */
%start input
%type <unit> input

%% 

/* Grammar rules */

input:
  /* empty */  { }
  | NEWLINE { } 
  | model NEWLINE {  }
;

model: 
  /* empty */                   { [] }
  | constraintPred              { [$1] }
  | constraintPred COMMA model  { $1 :: $3 }
  | LCURLY model RCURLY         { $2 }
;

constraintPred:
  | IN LPAREN QUOTE formula QUOTE COMMA contextVar RPAREN {
    let f = deBruijn true $4 in
    Constraints.IN(f, $7) 
  }
  | ELIN LPAREN QUOTE formula QUOTE COMMA contextVar RPAREN { 
    let f = deBruijn true $4 in
    Constraints.ELIN(f, $7) 
  }
  | EMP LPAREN contextVar RPAREN { 
    Constraints.EMP($3) 
  }
  | UNION LPAREN contextVar COMMA contextVar COMMA contextVar RPAREN { 
    Constraints.UNION($3, $5, $7) 
  }
  | REQIN LPAREN QUOTE formula QUOTE COMMA contextVar RPAREN { 
    let f = deBruijn true $4 in
    Constraints.REQIN(f, $7) 
  }
  ;

contextVar: 
  | NAME UNDERSCORE INDEX { ($1, $3) }
;

formula:
  | pred  { $1 }
  | TOP   { TOP }
  | BOT   { BOT }
  | ONE   { ONE }
  | ZERO  { ZERO }
  | LBRACKET subexp RBRACKET BANG formula   { BANG ($2,$5) }
  | LBRACKET subexp RBRACKET HBANG formula  { HBANG ($2,$5) }
  | LBRACKET subexp RBRACKET QST formula    { QST ($2,$5) }
  | BANG formula             { BANG (CONST("$infty"),$2) }
  | HBANG formula            { HBANG (CONST("$infty"),$2) }
  | QST formula              { QST (CONST("$infty"),$2) }
  | FORALL formula           { FORALL ($1, 0, $2) } 
  | EXISTS formula           { EXISTS ($1, 0, $2) }
  | ABS formula              { ABS($1, 0, $2) }
  | formula TIMES formula    { TENSOR ($1, $3)}
  | formula PLUS formula     { ADDOR ($1, $3)}
  | formula PIPE formula     { PARR ($1, $3)}
  | formula WITH formula     { WITH ($1, $3)}
  /* a [s]-o b is stored as LOLLI(s, b, a) */
  | formula LBRACKET subexp RBRACKET LOLLI formula { LOLLI ($3, $6, $1)}
  | LPAREN formula RPAREN    { $2 }
  | NEW formula              { NEW ($1, $2) }
  | NOT formula              { nnf (NOT($2)) }
;

pred:
  | NAME         { PRED ($1, CONST($1), NEG) } 
  | NAME terms   { PRED ($1, APP(CONST($1), $2), NEG ) }
  | VAR          { VAR {str = $1; id = 0; tag = LOG; ts = 0; lts = 0} }
  | VAR terms { 
    let var_head =  VAR {str = $1; id = 0; tag = LOG; ts = 0; lts = 0} in
    APP(var_head, $2)
  }
;

terms:
  | term                        { [$1] }
  | term terms                  { $1 :: $2 }
  | LPAREN terms RPAREN         { [make_APP $2] }
  | LPAREN terms RPAREN terms   { (make_APP $2) :: $4 } 
;

term:
  | NAME     { CONST ($1) }
  | VAR      { VAR {str = $1; id = 0; tag = LOG; ts = 0; lts = 0} }  
  | STRING   { STRING ($1) }
;

subexp:
  | NAME { CONST ($1) }
;

%%

