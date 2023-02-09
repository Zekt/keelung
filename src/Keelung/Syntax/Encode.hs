{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Module for converting Kinded syntax to Typed syntax
module Keelung.Syntax.Encode (Encode (..), runHeapM, encode') where

import Control.Monad.Reader
import Data.Array.Unboxed qualified as Array
import Data.IntMap qualified as IntMap
import GHC.TypeLits (KnownNat)
import Keelung.Heap
import Keelung.Syntax (widthOf)
import Keelung.Syntax qualified as Kinded
import Keelung.Syntax.Encode.Syntax

--------------------------------------------------------------------------------

-- | MultiParam version of 'Encode'
class Encode' a b where
  encode' :: a -> HeapM b

instance Encode' Kinded.Boolean Boolean where
  encode' expr = case expr of
    Kinded.Boolean b -> return $ ValB b
    Kinded.VarB var -> return $ VarB var
    Kinded.VarBI var -> return $ VarBI var
    Kinded.And x y -> AndB <$> encode' x <*> encode' y
    Kinded.Or x y -> OrB <$> encode' x <*> encode' y
    Kinded.Xor x y -> XorB <$> encode' x <*> encode' y
    Kinded.Not x -> NotB <$> encode' x
    Kinded.IfB p x y -> IfB <$> encode' p <*> encode' x <*> encode' y
    Kinded.EqB x y -> EqB <$> encode' x <*> encode' y
    Kinded.EqF x y -> EqF <$> encode' x <*> encode' y
    Kinded.EqU x y -> EqU (widthOf x) <$> encode' x <*> encode' y
    Kinded.BitU x i -> BitU (widthOf x) <$> encode' x <*> pure i

instance Encode' Kinded.Field Field where
  encode' expr = case expr of
    Kinded.Integer n -> return $ ValF n
    Kinded.Rational n -> return $ ValFR n
    Kinded.VarF var -> return $ VarF var
    Kinded.VarFI var -> return $ VarFI var
    Kinded.Add x y -> AddF <$> encode' x <*> encode' y
    Kinded.Sub x y -> SubF <$> encode' x <*> encode' y
    Kinded.Mul x y -> MulF <$> encode' x <*> encode' y
    Kinded.Div x y -> DivF <$> encode' x <*> encode' y
    Kinded.IfF p x y -> IfF <$> encode' p <*> encode' x <*> encode' y
    Kinded.BtoF b -> BtoF <$> encode' b

instance KnownNat w => Encode' (Kinded.UInt w) UInt where
  encode' expr = case expr of
    Kinded.UInt n -> return $ ValU (widthOf expr) n
    Kinded.VarU var -> return $ VarU (widthOf expr) var
    Kinded.VarUI var -> return $ VarUI (widthOf expr) var
    Kinded.AddU x y -> AddU (widthOf x) <$> encode' x <*> encode' y
    Kinded.SubU x y -> SubU (widthOf x) <$> encode' x <*> encode' y
    Kinded.MulU x y -> MulU (widthOf x) <$> encode' x <*> encode' y
    Kinded.AndU x y -> AndU (widthOf expr) <$> encode' x <*> encode' y
    Kinded.OrU x y -> OrU (widthOf expr) <$> encode' x <*> encode' y
    Kinded.XorU x y -> XorU (widthOf expr) <$> encode' x <*> encode' y
    Kinded.NotU x -> NotU (widthOf expr) <$> encode' x
    Kinded.IfU p x y -> IfU (widthOf expr) <$> encode' p <*> encode' x <*> encode' y
    Kinded.RoLU w i x -> RoLU w i <$> encode' x
    Kinded.ShLU w i x -> ShLU w i <$> encode' x
    Kinded.BtoU n -> BtoU (widthOf expr) <$> encode' n

--------------------------------------------------------------------------------

-- | Typeclass for encoding stuff into something Keelung can understand
class Encode a where
  encode :: a -> HeapM Expr

instance Encode Kinded.Boolean where
  encode expr = Boolean <$> encode' expr

instance Encode Kinded.Field where
  encode expr = Field <$> encode' expr

instance KnownNat w => Encode (Kinded.UInt w) where
  encode expr = UInt <$> encode' expr

instance Encode () where
  encode expr = case expr of
    () -> return Unit

instance Encode t => Encode (ArrM t) where
  encode expr = case expr of
    ArrayRef _ len addr -> readArray addr len

instance Encode t => Encode [t] where
  encode xs = Array . Array.listArray (0, length xs - 1) <$> mapM encode xs

instance (Encode a, Encode b) => Encode (a, b) where
  encode (a, b) = do
    a' <- encode a
    b' <- encode b
    return $ Array $ Array.listArray (0, 1) [a', b']

--------------------------------------------------------------------------------

-- | Reader Monad for Heap lookups
type HeapM = Reader Heap

runHeapM :: Heap -> HeapM a -> a
runHeapM h m = runReader m h

readArray :: Addr -> Int -> HeapM Expr
readArray addr len = Array <$> mapM (readHeap addr) indices
  where
    indices :: Array.Array Int Int
    indices = Array.listArray (0, pred len) [0 .. pred len]

    readHeap :: Addr -> Int -> HeapM Expr
    readHeap addr' i = do
      heap <- ask
      case IntMap.lookup addr' heap of
        Nothing -> error "HeapM: address not found"
        Just (elemType, array) -> case IntMap.lookup i array of
          Nothing -> error "HeapM: index ouf of bounds"
          Just addr'' -> case elemType of
            ElemF -> return $ Field $ VarF addr''
            ElemB -> return $ Boolean $ VarB addr''
            ElemU w -> return $ UInt $ VarU w addr''
            ElemArr _ len' -> readArray addr'' len'
            EmptyArr -> readArray addr'' 0
