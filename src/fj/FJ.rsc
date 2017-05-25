module fj::FJ

// Featherweight Java

extend ScopeGraph;
extend Constraints;
extend ExtractScopesAndConstraints;
extend TestFramework;
import ParseTree;
import String;

// ----  FJ syntax ---------------------------------------

lexical ClassId  = ([A-Z][a-z0-9]* !>> [a-z0-9]) \ Reserved;
lexical Id  = ([a-z][a-z0-9]* !>> [a-z0-9]) \ Reserved;
lexical Integer = [0-9]+ !>> [0-9]; 

keyword Reserved = "class" | "extends" | /*"super" |*/ "this" | "return";

layout Layout = WhitespaceAndComment* !>> [\ \t\n\r%];

lexical WhitespaceAndComment 
   = [\ \t\n\r]
   | @category="Comment" ws2:
    "%" ![%]+ "%"
   | @category="Comment" ws3: "{" ![\n}]*  "}"$
   ;
   
syntax Program
    = ClassDecl* classdecls
    ;
    
syntax ClassDecl
    = "class" ClassId cid "extends" ClassId ecid "{" 
              FieldDecl* fielddecls
              ConstructorDecl constructordecl
              MethodDecl* methoddecls
        "}"
     ;

syntax FieldDecl
    = ClassId cid Id id ";"
    ;

syntax ConstructorDecl
    =  ClassId cid Formals formals "{"
            SuperCall supercall
            FieldAssignment* fieldAssignments
       "}"
    ;

syntax SuperCall
    = Class super "(" {Variable ","}* vars ")" ";"
    ;
    
syntax Formal
    =  ClassId cid Id id
    ;
    
syntax Formals
    = "(" {Formal ","}* formals ")"
    ;
          
syntax MethodDecl
    = ClassId cid Id mid Formals formals "{" "return" Expression exp ";" "}"
    ;
    
syntax Expression
    = Variable var
    | Expression exp "." Field field
    | Expression exp "." Method method Expressions exps
    | "new" Constructor constructor Expressions exps
    | "(" Class class ")" Expression exp
    | "this"
    ;

syntax Constructor
    = ClassId id
    ;
syntax Class
    = ClassId id
    | "super"
    ;
    
syntax Variable
    = Id id
    ;
 
syntax Field
    = Id id
    ;

syntax Method
    = Id id
    ;
           
syntax Expressions
    = "(" {Expression ","}* expressions ")"
    ;   

syntax FieldAssignment
    = "this" "." Field field "=" Expression exp ";"
    ;   
    
// ----  IdRoles, PathLabels and AType ------------------- 

data IdRole
    = classId()
    | constructorId()
    | methodId()
    | fieldId()
    | formalId()
    ;

data PathLabel
    = extendsLabel()
    ;

data AType
    = classType(str cname, Use use)
    | methodType(AType returnType, AType argTypes)
    ;

AType classType(Tree scope, Tree cname) = classType("<cname>", use("<cname>", cname@\loc, scope@\loc, {classId()}));

AType useClassType(Tree scope, Tree cname){
    return useType(use("<cname>", cname@\loc, scope@\loc, {classId()}));
}

str AType2String(useType(Use use)) = "<use.id>";
str AType2String(methodType(AType returnType, AType argTypes)) 
    = "method <AType2String(returnType)>(<AType2String(argTypes)>)";
str AType2String(classType(str cname, _)) = cname;

// ---- isSubtype

bool isSubtype(AType atype1, AType atype2, ScopeGraph sg){
     //println("isSubType: <atype1>\n\t<atype2>");
     //iprintln(sg);
    if(c1: useType(Use use1) := atype1){
        try { 
            def1 = lookup(sg, use1);
            //println("use1: <use1>, def1: <def1>, <sg.facts[def1]?>");
            //iprintln(sg.facts);
            return isSubtype(sg.facts[def1], atype2, sg);
        } catch noKey: {
            return false;
        }
    }
    if(c2: useType(Use use2) := atype2){
        try { 
            def2 = lookup(sg, use2);
             //println("use2: <use2>, def2: <def2>");
            return isSubtype(atype1, sg.facts[def2], sg);
        } catch noKey: {
            return false;
        }
    }
    
    if(m1: methodType(AType returnType1, AType argTypes1) := atype1 &&
       m2: methodType(AType returnType2, AType argTypes2) := atype2){
        return isSubtype(returnType1, returnType2, sg) &&
               isSubtype(argTypes1, argTypes2, sg);
    }
    if(classType(_, _) := atype1 && classType("Object", _) := atype2){
        return true;
    }

    return atype1 == atype2;
}

bool isSubtype(listType(list[AType] atypes1), listType(list[AType] atypes2), ScopeGraph sg)
    = size(atypes1) == size(atypes2) &&
      (isEmpty(atypes1) || all(int i <- index(atypes1), isSubtype(atypes1[i], atypes2[i], sg)));

// ----  Initialize --------------------------------------  

SGBuilder initializedSGB(Tree scope){
    SGBuilder sgb = scopeGraphBuilder();
    // Simulate the definition of the class "Object"
    object_src = [ClassId] "Object";
    sgb.define(scope, "Object", classId(), object_src, defInfo(classType(scope, object_src)));
    super_src = [ClassId] "Super";
    sgb.define(scope, "super", constructorId(), super_src, defInfo(methodType(useClassType(scope, object_src), listType([]))));
    return sgb;
} 

// ----  Define -------------------------------------------------------

Tree define(ClassDecl cd, Tree scope, SGBuilder sgb)     {
    sgb.define(scope, "<cd.cid>", classId(), cd.cid, defInfo(classType(scope, cd.cid)));
    sgb.use_ref(scope, cd.ecid, {classId()}, extendsLabel(), 0); 
    sgb.define(scope, "this", fieldId(), cd.cid, defInfo(useClassType(scope, cd.cid)));  
    
    consDecl = cd.constructordecl;
    if(cd.cid != consDecl.cid){
        sgb.error(consDecl.cid, "Class name `<cd.cid>` differs from constructor name `<consDecl.cid>`");
    } else {
        superCall = consDecl.supercall;
        superType = typeof(cd.ecid, superCall.super, {constructorId()});
        superArgTypes = listType([ typeof(var) | Variable var <- superCall.vars ]);
        if("<cd.ecid>" == "Object"){
           sgb.define(scope, "super", classId(), cd.ecid, defInfo(useClassType(scope, cd.ecid)));
           if(size(superArgTypes.atypes) != 0){
              sgb.error(superCall, "Incorrect super arguments");
           }
        } else {   
            sgb.define(scope, "super", classId(), cd.ecid, defInfo(typeof(cd.ecid)));
            sgb.require("super call in <cd.ecid>", superCall,
            [ match(methodType(tau(1), tau(2)), superType, onError(superCall, "Wrong constructor type")),
              subtype(tau(2), superArgTypes, onError(superCall, "Incorrect super arguments"))
            ]);
        }
    }
    return cd;
}

Tree define(ConstructorDecl cons, Tree scope, SGBuilder sgb){
    tp = methodType(useClassType(scope, cons.cid), listType([useClassType(scope, f.cid) | Formal f <- cons.formals.formals]));
    sgb.define(scope, "<cons.cid>", constructorId(), cons.cid, defInfo(tp));

    return cons;                      
}

Tree define(fm: (Formal) `<ClassId cid> <Id id>`, Tree scope, SGBuilder sgb){
    sgb.define(scope, "<id>", formalId(), id, defInfo(useClassType(scope, cid)));
    return scope;
}

Tree define(fd: (FieldDecl) `<ClassId cid> <Id id> ;`, Tree scope, SGBuilder sgb){
    sgb.define(scope, "<id>", fieldId(), id, defInfo(useClassType(scope, cid)));
    return scope; 
}

Tree define(md: (MethodDecl) `<ClassId cid> <Id mid> <Formals formals> { return <Expression exp> ; }`, Tree scope,  SGBuilder sgb){   
    resType = useClassType(scope, cid); 
    argTypes = listType([useClassType(scope, f.cid) | Formal f <- formals.formals]);
   
    sgb.define(scope, "<mid>", methodId(), mid, defInfo(methodType(resType, argTypes)));
    sgb.require("method definition <mid>", md,
        [subtype(typeof(exp), resType, onError(md, "Actual return type should be subtype of declared return type"))
        ]);
    return md;
}

// ----  Collect uses & requirements ------------------------------------

void collect(Class c, Tree scope, SGBuilder sgb){
    if("<c>" == "super"){
      sgb.use(scope, c, {classId()}, 0);
    } else {
      sgb.use(scope, c.id, {classId()}, 0);
    }
}

void collect(Constructor c, Tree scope, SGBuilder sgb){
    sgb.use(scope, c.id, {constructorId()}, 0);
}

void collect(Variable var, Tree scope, SGBuilder sgb){
    sgb.use(scope, var.id, {formalId(), fieldId()}, 0);
}

void collect(Field fld, Tree scope, SGBuilder sgb){
    sgb.use(scope, fld.id, {fieldId()}, 0);
}

void collect(Method mtd, Tree scope, SGBuilder sgb){
    sgb.use(scope, mtd.id, {methodId()}, 0);
}

void collect(sc: (SuperCall) `<Class super> ( <{Variable ","}* vars> );`, Tree scope, SGBuilder sgb){
    sgb.require("super call", sc,
        [ match(methodType(tau(1), tau(2)), typeof(super, super, {constructorId()}), onError(sc, "Incorrect super call")),
          fact(sc, tau(1))
        ]);
}

void collect(e: (Expression) `<Expression exp> . <Field field>`, Tree scope, SGBuilder sgb){
    if("<exp>" == "this"){
        sgb.fact(e, typeof(field.id));
    } else {
        sgb.fact(e, typeof(exp, field.id, {fieldId()}));
    }
}

void collect(e: (Expression) `<Expression exp> . <Method method> <Expressions exps>`, Tree scope, SGBuilder sgb){
    argTypes = listType([ typeof(arg) | arg <- exps.expressions ]); 
    sgb.require("method call `<method>`", e,
                [ match(methodType(tau(1), tau(2)), typeof(exp, method.id, {methodId()}), onError(e, "Method required")),
                  subtype(argTypes, tau(2), onError(e, "Incorrect method arguments")),
                  fact(e, tau(1)) 
                ]);
}

void collect(e: (Expression) `new <Constructor cons> <Expressions exps>`, Tree scope, SGBuilder sgb){
    returnType = useClassType(scope, cons.id);
    argTypes = listType([ typeof(exp) | exp <- exps.expressions ]);
    
    sgb.require("new `<cons>`", e,
        [ subtype(methodType(returnType, argTypes), typeof(cons), onError(e, "Incorrect constructor arguments")),
          fact(e, returnType) 
        ]);
}

void collect(e: (Expression) `( <ClassId cid> ) <Expression exp>`, Tree scope, SGBuilder sgb){  // <++++++
    castType = useClassType(scope, cid);
    sgb.require("cast `<cid>`", e,
        [ subtype(typeof(exp), castType, onError(e, "Incorrect cast")),
          fact(e, castType) 
        ]);
}

void collect(e: (Expression) `this`, Tree scope, SGBuilder sgb){
     sgb.use(scope, e, {fieldId()}, 0);
}

// ----  Examples & Tests --------------------------------

private Program sample(str name) = parse(#Program, |project://TypePal/src/fj/<name>.fj|);

set[Message] validateFJ(str name) {
    p = sample(name);
    return validate(extractScopesAndConstraints(p, initializedSGB(p)), isSubtype=isSubtype);
}

void testFJ() {
    runTests(|project://TypePal/src/fj/tests.ttl|, #Program, initialSGBuilder = initializedSGB);
}