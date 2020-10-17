{-# LANGUAGE RecordWildCards, LambdaCase, OverloadedStrings #-}
module Stg.Interpreter.Base where

import Control.Monad.State
import Data.Map (Map)
import qualified Data.Map as Map
import Data.IntMap (IntMap)
import qualified Data.IntMap as IntMap
import Data.ByteString.Char8 (ByteString)
import qualified Data.ByteString.Char8 as BS8
import Data.Vector (Vector)

import Text.Printf
import Debug.Trace
import Stg.Syntax

newtype Id = Id {unId :: Binder}

instance Eq Id where
  (Id a) == (Id b) = binderUniqueName a == binderUniqueName b -- FIXME: make this fast

instance Ord Id where
  compare (Id a) (Id b) = compare (binderUniqueName a) (binderUniqueName b) -- FIXME: make this fast

instance Show Id where
  show (Id a) = BS8.unpack $ binderUniqueName a

type StgRhsClosure = Rhs  -- NOTE: must be StgRhsClosure only!

data HeapObject
  = Con
    { hoCon         :: DataCon
    , hoConArgs     :: [Atom]
    }
  | Closure
    { hoName        :: Id
    , hoCloBody     :: StgRhsClosure
    , hoEnv         :: Env    -- local environment ; with live variables only, everything else is pruned
    , hoCloArgs     :: [Atom]
    , hoCloMissing  :: Int    -- HINT: this is a Thunk if 0 arg is missing ; if all is missing then Fun ; Pap is some arg is provided
    }
  | Blackhole HeapObject
  deriving (Show, Eq, Ord)

data StackContinuation
  = CaseOf  Id AltType [Alt]  -- pattern match on the result
  | Update  Addr                  -- update Addr with the result heap object ; NOTE: maybe this is irrelevant as the closure interpreter will perform the update if necessary
  | Apply   [Atom]                -- apply args on the result heap object
  deriving (Show, Eq, Ord)

data ArrIdx
  = MutArrIdx !Int
  | ArrIdx    !Int
  deriving (Show, Eq, Ord)

data SmallArrIdx
  = SmallMutArrIdx !Int
  | SmallArrIdx    !Int
  deriving (Show, Eq, Ord)


data Atom     -- Q: should atom fit into a cpu register?
  = HeapPtr   !Addr
  | Literal   !Lit             -- Q: should we allow string literals, or should string lits be modeled as StringPtr?
  | StringPtr !Int !ByteString  -- HINT: StgTopStringLit ; maybe include its origin? ; the PrimRep is AddrRep
  | Void
  | FloatAtom     !Float
  | DoubleAtom    !Double
  | StablePointer !Atom -- TODO: need proper implementation
  | MVar          !Int
  | Array         !ArrIdx
  | MutableArray  !ArrIdx
  | SmallArray         !SmallArrIdx
  | SmallMutableArray  !SmallArrIdx
  | MutVar        !Int
  | MutableByteArray
  | ByteArray
  | WeakPointer
  | ThreadId
  deriving (Show, Eq, Ord)

type ReturnValue = [Atom]

type Addr   = Int
type Heap   = IntMap HeapObject
type Env    = Map Id Atom   -- NOTE: must contain only the defined local variables
type Stack  = [(Env, StackContinuation)]

{-
  Q: do we want homogeneous or heterogeneous Heap ; e.g. single intmap with mixed things or multiple intmaps/vector with multiple address spaces
-}


data StgState
  = StgState
  { ssHeap      :: !Heap
  , ssEnv       :: !Env
--  , ssStack     :: [(Env, StackContinuation)] -- TODO: use reified stack instead of the host language stack
  , ssEvalStack :: [Id]
  , ssNextAddr  :: !Int

  -- primop related

  , ssMVars         :: IntMap (Maybe Atom)
  , ssArrays        :: IntMap (Vector Atom)
  , ssMutableArrays :: IntMap (Vector Atom)
  , ssSmallArrays        :: IntMap (Vector Atom)
  , ssSmallMutableArrays :: IntMap (Vector Atom)
  , ssMutVars       :: IntMap Atom
  }
  deriving (Show, Eq, Ord)

emptyStgState :: StgState
emptyStgState = StgState
  { ssHeap      = mempty
  , ssEnv       = mempty
  , ssEvalStack = []
  , ssNextAddr  = 0
  , ssMVars         = mempty
  , ssArrays        = mempty
  , ssMutableArrays = mempty
  , ssMutVars       = mempty
  }

type M = State StgState

freshHeapAddress :: M Addr
freshHeapAddress = state $ \s@StgState{..} -> (ssNextAddr, s {ssNextAddr = succ ssNextAddr})

allocAndStore :: HeapObject -> M Addr
allocAndStore o = do
  a <- freshHeapAddress
  store a o
  pure a

store :: Addr -> HeapObject -> M ()
store a o = modify' $ \s -> s {ssHeap = IntMap.insert a o (ssHeap s)}

addEnv :: Binder -> Atom -> M ()
addEnv b a = modify' $ \s -> s {ssEnv = Map.insert (Id b) a (ssEnv s)}

stgErrorM :: String -> M a
stgErrorM msg = do
  es <- gets ssEvalStack
  error $ unlines ["eval stack:", show es, msg]

lookupEnv :: Binder -> M Atom
lookupEnv b
 | binderId b == BinderId (Unique '0' 21) -- void#
 = pure Void
 | binderId b == BinderId (Unique '0' 15) -- realWorld#
 = pure Void
 | otherwise
 = do
  env <- gets ssEnv
  case Map.lookup (Id b) env of
    Nothing -> stgErrorM $ "unknown variable: " ++ show b
    Just a  -> pure a

update :: Atom -> [Atom] -> M [Atom]
update (HeapPtr dst) result@[src] = do
  o <- readHeap src
  store dst o
  pure result

withEnv :: Id -> Env -> M a -> M a
withEnv i env m = do
  save <- gets ssEnv
  saveES <- gets ssEvalStack
  modify' $ \s -> s {ssEnv = env, ssEvalStack = [i]}
  res <- trace (printf "eval %-40s %s" (BS8.unpack . getModuleName . binderModule $ unId i) (show i)) $ m
  modify' $ \s -> s {ssEnv = save, ssEvalStack = saveES}
  pure res

readHeap :: Atom -> M HeapObject
readHeap (HeapPtr l) = do
  h <- gets ssHeap
  case IntMap.lookup l h of
    Nothing -> stgErrorM $ "unknown heap address: " ++ show l
    Just o  -> pure o

readHeapCon :: Atom -> M HeapObject
readHeapCon a = readHeap a >>= \o -> case o of
    Con{} -> pure o
    _     -> stgErrorM $ "expected con but got: " ++ show o

-- primop related

type PrimOpEval = Name -> [Atom] -> Type -> Maybe TyCon -> M [Atom]

type BuiltinStgEval = Atom -> M [Atom]
type BuiltinStgApply = Atom -> [Atom] -> M [Atom]

lookupMutVar :: Int -> M Atom
lookupMutVar m = do
  IntMap.lookup m <$> gets ssMutVars >>= \case
    Nothing -> stgErrorM $ "unknown MutVar: " ++ show m
    Just a  -> pure a

lookupMVar :: Int -> M (Maybe Atom)
lookupMVar m = do
  IntMap.lookup m <$> gets ssMVars >>= \case
    Nothing -> stgErrorM $ "unknown MVar: " ++ show m
    Just a  -> pure a

lookupArray :: Int -> M (Vector Atom)
lookupArray m = do
  IntMap.lookup m <$> gets ssArrays >>= \case
    Nothing -> stgErrorM $ "unknown Array: " ++ show m
    Just a  -> pure a

lookupMutableArray :: Int -> M (Vector Atom)
lookupMutableArray m = do
  IntMap.lookup m <$> gets ssMutableArrays >>= \case
    Nothing -> stgErrorM $ "unknown MutableArray: " ++ show m
    Just a  -> pure a

lookupSmallArray :: Int -> M (Vector Atom)
lookupSmallArray m = do
  IntMap.lookup m <$> gets ssSmallArrays >>= \case
    Nothing -> stgErrorM $ "unknown SmallArray: " ++ show m
    Just a  -> pure a

lookupSmallMutableArray :: Int -> M (Vector Atom)
lookupSmallMutableArray m = do
  IntMap.lookup m <$> gets ssSmallMutableArrays >>= \case
    Nothing -> stgErrorM $ "unknown SmallMutableArray: " ++ show m
    Just a  -> pure a