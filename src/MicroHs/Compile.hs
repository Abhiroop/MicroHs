-- Copyright 2023 Lennart Augustsson
-- See LICENSE file for full license.
module MicroHs.Compile(
  compileTop,
  Flags(..), verbose, runIt, output,
  compileCacheTop,
  Cache, emptyCache, deleteFromCache,
  ) where
import Prelude --Xhiding (Monad(..), mapM, showString, showList)
import qualified System.IO as IO
import Control.DeepSeq
import qualified MicroHs.IdentMap as M
import MicroHs.StateIO as S
import MicroHs.Desugar
import MicroHs.Exp
import MicroHs.Expr
import MicroHs.Ident
import MicroHs.Parse
import MicroHs.TypeCheck
--Ximport Compat
--Ximport qualified CompatIO as IO
--Ximport System.IO(Handle)

data Flags = Flags Int Bool [String] String
  --Xderiving (Show)

type Time = Int

verbose :: Flags -> Int
verbose (Flags x _ _ _) = x

runIt :: Flags -> Bool
runIt (Flags _ x _ _) = x

paths :: Flags -> [String]
paths (Flags _ _ x _) = x

output :: Flags -> String
output (Flags _ _ _ x) = x

-----------------

type CModule = TModule [LDef]
data Cache = Cache [IdentModule] (M.Map CModule)
  --Xderiving (Show)

working :: Cache -> [IdentModule]
working (Cache x _) = x

updWorking :: [IdentModule] -> Cache -> Cache
updWorking w (Cache _ m) = Cache w m

cache :: Cache -> M.Map CModule
cache (Cache _ x) = x

emptyCache :: Cache
emptyCache = Cache [] M.empty

deleteFromCache :: Ident -> Cache -> Cache
deleteFromCache mn (Cache is m) = Cache is (M.delete mn m)

-----------------

compileCacheTop :: Flags -> Ident -> Cache -> IO ([(Ident, Exp)], Cache)
compileCacheTop flags mn ch = IO.do
  (ds, ch') <- compile flags mn ch
  t1 <- getTimeMilli
  let
    dsn = [ (n, compileOpt e) | (n, e) <- ds ]
  () <- IO.return (rnf dsn)
  t2 <- getTimeMilli
  IO.when (verbose flags > 0) $
    putStrLn $ "combinator conversion " ++ padLeft 6 (showInt (t2-t1)) ++ "ms"
  IO.return (dsn, ch')

--compileTop :: Flags -> IdentModule -> IO [LDef]
compileTop :: Flags -> Ident -> IO [(Ident, Exp)]
compileTop flags mn = IO.fmap fst $ compileCacheTop flags mn emptyCache

compile :: Flags -> IdentModule -> Cache -> IO ([LDef], Cache)
compile flags nm ach = IO.do
  ((_, t), ch) <- runStateIO (compileModuleCached flags nm) ach
  let
    defs (TModule _ _ _ _ _ ds) = ds
  IO.when (verbose flags > 0) $
    putStrLn $ "total import time     " ++ padLeft 6 (showInt t) ++ "ms"
  IO.return (concatMap defs $ M.elems $ cache ch, ch)

-- Compile a module with the given name.
-- If the module has already been compiled, return the cached result.
compileModuleCached :: Flags -> IdentModule -> StateIO Cache (CModule, Time)
compileModuleCached flags nm = S.do
  ch <- gets cache
  case M.lookup nm ch of
    Nothing -> S.do
      ws <- gets working
      S.when (elemBy eqIdent nm ws) $
        error $ "recursive module: " ++ showIdent nm
      modify $ \ c -> updWorking (nm : working c) c
      S.when (verbose flags > 0) $
        liftIO $ putStrLn $ "importing " ++ showIdent nm
      (cm, tp, tt, ts) <- compileModule flags nm
      S.when (verbose flags > 0) $
        liftIO $ putStrLn $ "importing done " ++ showIdent nm ++ ", " ++ showInt (tp + tt) ++
                 "ms (" ++ showInt tp ++ " + " ++ showInt tt ++ ")"
      c <- get
      put $ Cache (tail (working c)) (M.insert nm cm (cache c))
      S.return (cm, tp + tt + ts)
    Just cm -> S.do
      S.when (verbose flags > 0) $
        liftIO $ putStrLn $ "importing cached " ++ showIdent nm
      S.return (cm, 0)

-- Find and compile a module with the given name.
-- The times are (parsing, typecheck+desugar, imported modules)
compileModule :: Flags -> IdentModule -> StateIO Cache (CModule, Time, Time, Time)
compileModule flags nm = S.do
  t1 <- liftIO getTimeMilli
  let
    fn = map (\ c -> if eqChar c '.' then '/' else c) (unIdent nm) ++ ".hs"
  (pathfn, file) <- liftIO (readFilePath (paths flags) fn)
  let mdl@(EModule nmn _ defs) = parseDie pTop pathfn file
  --liftIO $ putStrLn $ showEModule mdl
  S.when (not (eqIdent nm nmn)) $
    error $ "module name does not agree with file name: " ++ showIdent nm ++ " " ++ showIdent nmn
  let
    specs = [ s | Import s <- defs ]
  t2 <- liftIO getTimeMilli
  (impMdls, ts) <- S.fmap unzip $ S.mapM (compileModuleCached flags) [ m | ImportSpec _ m _ _ <- specs ]
  t3 <- liftIO getTimeMilli
  let
    tmdl = typeCheck (zip specs impMdls) mdl
  S.when (verbose flags > 2) $
    liftIO $ putStrLn $ "type checked:\n" ++ showTModule showEDefs tmdl ++ "-----\n"
  let
    dmdl = desugar tmdl
  liftIO $ putStr $ drop 1000000 $ showTModule showLDefs dmdl
  t4 <- liftIO getTimeMilli
  S.when (verbose flags > 2) $
    (liftIO $ putStrLn $ "desugared:\n" ++ showTModule showLDefs dmdl)
  S.return (dmdl, t2-t1, t4-t3, sum ts)

------------------

readFilePath :: [FilePath] -> FilePath -> IO (FilePath, String)
readFilePath path name = IO.do
  mh <- openFilePath path name
  case mh of
    Nothing -> error $ "File not found: " ++ showString name ++ "\npath=" ++ showList showString path
    Just (fn, h) -> IO.do
      file <- IO.hGetContents h
      IO.return (fn, file)

openFilePath :: [FilePath] -> FilePath -> IO (Maybe (FilePath, Handle))
openFilePath adirs fileName =
  case adirs of
    [] -> IO.return Nothing
    dir:dirs -> IO.do
      let
        path = dir ++ "/" ++ fileName
      mh <- openFileM path IO.ReadMode
      case mh of
        Nothing -> openFilePath dirs fileName -- If opening failed, try the next directory
        Just hdl -> IO.return (Just (path, hdl))
