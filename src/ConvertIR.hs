module ConvertIR where

import Grammar as AST
import qualified Intermediate as IR
import Paskell (parseProgram)
import TypeCheck (typechkProgram, TyErr)

import Utils (p')
import Data.List

-- Environment is a Func/Proc signatures + stack of Contexts
type Env = (Sig, [Context]) 
-- Function sig is return type + formal args types
type Sig = [(Ident, (Type, [Type]))]
type Context = [(Ident, Type)]


varInContext :: Context -> Ident -> Bool
varInContext ctx x = case (lookup x ctx) of 
    Nothing -> False
    Just _  -> True

lookupVar   :: Env -> Ident -> Type
lookupVar (_, contexts) x = case (find (`varInContext` x) contexts) of
                    Just ctx -> case lookup x ctx of
                        Just t   -> t

lookupFun   :: Env -> Ident -> (Type, [Type])
lookupFun (sigs, _) x = 
    case lookup x sigs of Just f  -> f

newBlock  :: Env -> Env
newBlock (sig, contexts) = (sig, [] : contexts)

emptyEnv  :: Env
emptyEnv = ([], [])

getSig :: Decl -> (Ident, (Type, [Type]))
getSig (DeclFunc x args t _) = (x, (t, map (\(_,b,_) -> b) args))

-- updateVar :: Env -> Ident -> Type -> Either TyErr Env

addVar :: Env -> Ident -> Type -> Env
addVar (sig , (c:cs)) x t = (sig, ((x,t):c) : cs)

addFunc :: Env -> (Ident, (Type, [Type])) -> Env
addFunc (sigs, ctx) (x, rest) = case lookup x sigs of
        Nothing  -> ((x, rest) : sigs, ctx)

isNum = (`elem` [TYint, TYreal])


convProgram :: Program -> IR.Program
convProgram (Program x b) = 
    IR.Program x (fst $ convBlock (newBlock emptyEnv) b) Void

convBlock :: Env -> Block -> (IR.Block, Env)
convBlock env (Block decls s)= let
    (decls', env') = convDecls env decls 
    s' = convStatement env' s in
    (IR.Block decls' s' Void, env)

convDecls :: Env -> [Decl] -> ([IR.Decl], Env)
convDecls env [] = ([], env)
convDecls env (d:ds) = let
    (ird, env')   = convDecl env d
    (irds, env'') = convDecls env' ds in
    (ird:irds, env'')

convDecl :: Env -> Decl -> (IR.Decl, Env)
convDecl env (DeclVar xs) = let 
    addVar' (a',b') c' = addVar c' a' b'
    env'  = foldr addVar' env xs in
    (IR.DeclVar xs Void, env')
convDecl env df@(DeclFunc x params t b) = let
    xs   = map (\(a',b',_) -> (a',b')) params 
    addVar' (a',b') c' = addVar c' a' b'
    env'  = addFunc env (getSig df)
    env'' = foldr addVar' (newBlock env') xs in
    (IR.DeclFunc x params t (fst $ convBlock env'' b) Void, env')


convStatement :: Env -> Statement -> IR.Statement
convStatement env (Assignment des expr) = 
    IR.Assignment (convDesignator env des) (convExpr env expr) Void

convStatement env (StatementIf expr s1 ms2) =
    IR.StatementIf (convExpr env expr) (convStatement env s1) ((convStatement env) <$> ms2) Void


convStatement env (StatementFor i x1 b x2 s) = -- todo: add i to s's env?
    IR.StatementFor i (convExpr env x1) b (convExpr env x2) (convStatement env s) Void

convStatement env StatementEmpty = IR.StatementEmpty

convStatement env (StatementSeq xs) = IR.StatementSeq (map (convStatement env) xs) Void


convDesignator :: Env -> Designator -> IR.Designator
convDesignator env (Designator x _) = IR.Designator x [] (lookupVar env x) 

convExpr :: Env -> Expr -> IR.Expr
convExpr env FactorTrue        = IR.FactorTrue    TYbool
convExpr env FactorFalse       = IR.FactorFalse   TYbool
convExpr env (FactorInt x)     = IR.FactorInt  x  TYint
convExpr env (FactorReal x)    = IR.FactorReal x  TYreal
convExpr env (FactorStr x)     = IR.FactorStr  x  TYstr
convExpr env (FactorNot x)     = undefined

convExpr env (FuncCall x args) = 
    IR.FuncCall x (map (convExpr env) args) (fst $ lookupFun env x)

convExpr env (FactorDesig des) = let 
    (Designator x _) = des
    in IR.FactorDesig (convDesignator env des) (lookupVar env x)

convExpr env (Unary op x) = let 
    x' = convExpr env x
    in IR.Unary op x' (IR.getType x')

convExpr env (Relation x1 op x2) = let 
    x1' = convExpr env x1
    x2' = convExpr env x2 
    in IR.Relation x1' op x2' TYbool

convExpr env (Add x1 op x2) = let
    x1' = convExpr env x1
    x2' = convExpr env x2
    t1  = IR.getType x1' 
    t2  = IR.getType x2' 
    t   = if op `elem` [OPplus, OPminus] 
          then if t1 == TYreal then t1 else t2 
          else TYbool
    in IR.Add x1' op x2' t

convExpr env (Mult x1 op x2) = let    
    x1' = convExpr env x1
    x2' = convExpr env x2
    t1  = IR.getType x1' 
    t2  = IR.getType x2' 
    t   = if op `elem` [OPstar, OPdiv] 
            then if t1 == TYreal then t1 else t2 
            else TYbool
    in IR.Mult x1' op x2' t

chkConvPogram p = case typechkProgram p of
    Left err2 -> print err2
    Right ()  -> print $ convProgram p