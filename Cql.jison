%lex

%{
    var parser = yy.parser;
%}

%%
[\s+\t+] /* skip whitespace */
((a|A)(n|N)(d|D))|((o|O)(r|R))|((n|N)(o|O)(t|T))|((p|P)(r|R)(o|O)(x|X)) return 'BOOLEAN'
(s|S)(o|O)(r|R)(t|T)(b|B)(y|Y) return 'SORTBY'
"/" return 'MODIFIER_PREFIX'
">" return 'GREATER'
"=" return 'EQUAL'
"<"|">="|"<="|"<>"|"==" return 'COMPARITOR_SYMBOL_OTHER'
"(" return 'LEFT_PAREN'
")" return 'RIGHT_PAREN'
((a|A)(d|D)(j|J))|((a|A)(l|L)(l|L))|((a|A)(n|N)(y|Y))|((w|W)(i|I)(t|T)(h|H)(i|I)(n|N))|((e|E)(n|N)(c|C)(l|L)(o|O)(s|S)(e|E)(s|S)) return 'NAMED_COMPARITOR'
\"((\\\")|(\\\\)|((?!(\\|\")).))*\" return 'CHAR_STRING2'
[^\s\t\r\n\(\)=\<\>\/"]+ return 'CHAR_STRING1'
<<EOF>>  return 'EOF'

/lex

%start expressions

%%

expressions
    :sortedQuery EOF
        { return $1;}
    ;

index
    :identifier
        { $$ = $1; }
    ;

term
    :identifier
        { $$ = $1; }
    |BOOLEAN
        { $$ = yytext; }
    |NAMED_COMPARITOR
        { $$ = yytext; }
    |SORTBY
        { $$ = yytext; }
    ;

identifier
    :CHAR_STRING1
        { $$ = yytext; }
    |CHAR_STRING2
        { $$ = parser.UnpackQuotedString(yytext); }
    ;

relation
    :comparitorSymbol
        { $$ = $1; }
    |NAMED_COMPARITOR
        { $$ = yytext; }
    |identifier
        { $$ = $1; }
    ;

singleSearchTerm
    :identifier
        { $$ = $1; }
    |BOOLEAN
        { $$ = yytext; }
    |NAMED_COMPARITOR
        { $$ = yytext; }
    ;

comparitorSymbol
    :GREATER
        { $$ = yytext; }
    |EQUAL
        { $$ = yytext; }
    |COMPARITOR_SYMBOL_OTHER
        { $$ = yytext; }
    ;

modifier
    :MODIFIER_PREFIX term comparitorSymbol term
        { $$ = { name: $2, comparitor: $3, value: $4, type: 'CqlModifier' }; }
    |MODIFIER_PREFIX term
        { $$ = { name: $2, type: 'CqlModifier' }; }
    ;

modifiers
    :modifiers modifier
        { $$ = $1.concat([$2]) ;}
    |modifier
        { $$ = [$1]; }
    ;

relationGroup
    :relation modifiers
        { $$ = { relation: $1, modifiers: $2, type: 'CqlRelation' }; }
    |relation
        { $$ = { relation: $1, type: 'CqlRelation' }; }
    ;

boolean
    :BOOLEAN
        { $$ = yytext; }
    ;

booleanGroup
    :boolean modifiers
        { $$ = { boolean: $1, modifiers: $2, type: 'CqlBoolean' }; }
    |boolean
        { $$ = { boolean: $1, type: 'CqlBoolean' }; }
    ;

prefixAssignment
    :GREATER term EQUAL term
        { $$ = { name: $2, uri: $4, type: 'CqlPrefix' }; }
    |GREATER term
        { $$ = { uri: $2, type: 'CqlPrefix' }; }
    ;

prefixAssignments
    :prefixAssignments prefixAssignment
        { $$ = $1.concat([$2]); }
    |prefixAssignment
        { $$ = [$1]; }
    ;

moreScopedClause
    :booleanGroup searchClause
        { $$ = { boolean: $1, searchClause: $2 }; }
    ;

moreScopedClauses
    :moreScopedClauses moreScopedClause
        { $$ = $1.concat([$2]); }
    |moreScopedClause
        { $$ = [$1]; }
    ;

scopedClause
    :searchClause moreScopedClauses
        { $$ = parser.JoinClause($1, $2); }
    |searchClause
        { $$ = $1 }
    ;

cqlQuery
    :prefixAssignments scopedClause
        { $$ = { searchClause: $2, prefix: $1, type: 'CqlQuery' }; }
    |scopedClause
        { $$ = { searchClause: $1, type: 'CqlQuery' }; }
    ;

searchClause
    :LEFT_PAREN cqlQuery RIGHT_PAREN
        { $$ = $2.searchClause; }
    |index relationGroup term
        { $$ = { index: $1, relation: $2, terms: $3, type: 'CqlSimpleClause' }; }
    |singleSearchTerm
        { $$ = { index: 'cql.serverChoice', relation: '=', type: 'CqlSimpleClause' };}
    ;

singleSpec
    :term modifiers
        { $$ = { index: $1, modifiers: $2, type:'CqlSort' }; }
    |term
        { $$ = { index: $1, type:'CqlSort' }; }
    ;

singleSpecs
    :singleSpecs singleSpec
        { $$ = $1.concat([$2]); }
    |singleSpec
        { $$ = [$1]; }
    ;

sortSpec
    :SORTBY singleSpecs
        { $$ = $2; }
    ;

sortedQuery
    :cqlQuery sortSpec
        { $$ = { query: $1, sortKey: $2, type: 'Cql' }; }
    |cqlQuery
        { $$ = { query: $1, type: 'Cql' }; }
    |sortSpec
        { $$ = { sortKey: $1, type: 'Cql' }; }
    ;

%%

parser.UnpackQuotedString = function(text) {
    return text.substring(1, text.length - 1).replace('\\"', '"').replace('\\\\', '\\');
};

parser.JoinClause = function(thisClause, addedPair) {
    var root = thisClause;
    addedPair.forEach(function(pair) {
        root = parser.JoinClause2(root, pair.boolean, pair.searchClause);
    });
    return root;
};

parser.JoinClause2 = function(thisClause, addedBoolean, addedClause) {
    var result = { type: 'CqlComplexClause', left: thisClause, boolean: addedBoolean };
    thisClause.parent = result;
    result.right = addedClause;
    addedClause.parent = result;
    return result;
};