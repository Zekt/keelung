{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE StandaloneDeriving #-}

module Keelung.Field.N where

import Data.Euclidean (Euclidean, GcdDomain)
import Data.Field (Field)
import Data.Field.Galois (GaloisField (order))
import Data.Semiring (Ring, Semiring)
import Data.Serialize (Serialize)
import GHC.Generics (Generic)

-- import Data.Field.Galois (GaloisField(..))

--------------------------------------------------------------------------------

-- | Data type for displaying field numbers nicely
-- Numbers in the second half of the field are represented as negative numbers
newtype N a = N {unN :: a}
  deriving (Eq, Ord, Generic)

instance Serialize a => Serialize (N a)

deriving instance Bounded n => Bounded (N n)

deriving instance Field n => Field (N n)

deriving instance Euclidean n => Euclidean (N n)

deriving instance Ring n => Ring (N n)

deriving instance GcdDomain n => GcdDomain (N n)

deriving instance Semiring n => Semiring (N n)

deriving instance Fractional n => Fractional (N n)

deriving instance Num n => Num (N n)

deriving instance Enum n => Enum (N n)

deriving instance Real n => Real (N n)

instance (GaloisField n, Integral n) => Integral (N n) where
  quotRem n m = (N q, N r)
    where
      (q, r) = quotRem (unN n) (unN m)
  toInteger (N x) =
    let halfway = fromIntegral (order x `div` 2)
     in if x >= halfway
          then negate ((toInteger (order x) - toInteger x) + 1)
          else toInteger x

instance (GaloisField n, Integral n) => Show (N n) where
  show = show . toInteger . unN