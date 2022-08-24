{-# LANGUAGE DataKinds #-}

module Keelung
  ( module Keelung.Syntax,
    module Keelung.Field,
    module Keelung.Monad,
    compile,
    interpret,
    gf181,
    bn128,
    b64,
    elaborate,
    Kind (..),
    GaloisField,
  )
where

import qualified Data.ByteString.Char8 as BSC
import Data.Field.Galois (GaloisField)
import Data.Serialize
import Keelung.Constraint.R1CS (R1CS)
import Keelung.Error
import Keelung.Field
import Keelung.Monad
import Keelung.Syntax
import Keelung.Syntax.Simplify (simplify)
import qualified Keelung.Syntax.Typed as C
import Keelung.Types
import System.IO.Error
import qualified System.Info
import qualified System.Process as Process

-- | Compile a program to a 'R1CS' constraint system.
compile :: (Serialize n, Integral n, AcceptedField n) => Comp n (Val t n) -> IO (Either Error (R1CS n))
compile prog = case elaborate prog of
  Left err -> return $ Left (ElabError err)
  Right elab -> wrapper ["protocol", "toR1CS"] elab

-- | Interpret a program with inputs
interpret :: (Serialize n, Integral n, AcceptedField n) => Comp n (Val t n) -> [n] -> IO (Either Error [n])
interpret prog xs = case elaborate prog of
  Left err -> return $ Left (ElabError err)
  Right elab -> wrapper ["protocol", "interpret"] (elab, map toInteger xs)

--------------------------------------------------------------------------------

printErrorInstead :: (Serialize n, Integral n, AcceptedField n) => Comp n (Val t n) -> [n] -> IO [n]
printErrorInstead prog xs = do
  result <- interpret prog xs
  case result of
    Left err -> do
      print err
      return []
    Right values -> return values

-- | A specialized version of 'interpret' that outputs numbers as 'N GF181'
gf181 :: Comp GF181 (Val t GF181) -> [GF181] -> IO [N GF181]
gf181 prog xs = map N <$> printErrorInstead prog xs

-- | A specialized version of 'interpret' that outputs numbers as 'N B64'
b64 :: Comp B64 (Val t B64) -> [B64] -> IO [N B64]
b64 prog xs = map N <$> printErrorInstead prog xs

-- | A specialized version of 'interpret' that outputs numbers as 'N BN128'
bn128 :: Comp BN128 (Val t BN128) -> [BN128] -> IO [N BN128]
bn128 prog xs = map N <$> printErrorInstead prog xs

--------------------------------------------------------------------------------

-- | Elaborate a program
elaborate :: (Integral n, AcceptedField n) => Comp n (Val t n) -> Either ElabError C.Elaborated
elaborate prog = do
  (expr, comp') <- runComp emptyComputation prog
  return $ simplify $ Elaborated expr comp'

--------------------------------------------------------------------------------

-- | Internal function for handling data serialization
wrapper :: (Serialize a, Serialize b) => [String] -> a -> IO (Either Error b)
wrapper args' payload = do
  path <- findKeelungc
  case path of
    Nothing -> return $ Left InstallError
    Just (cmd, args) -> do
      blob <- Process.readProcess cmd (args ++ args') (BSC.unpack $ encode payload)
      let result = decode (BSC.pack blob)
      case result of
        Left err -> return $ Left $ DecodeError err
        Right (Left err) -> return $ Left $ CompileError err
        Right (Right x) -> return $ Right x

-- | Locate the Keelung compiler
--      1. see if "keelungc" is in PATH
--      2. if not, try to run "docker run banacorn/keelung"
findKeelungc :: IO (Maybe (String, [String]))
findKeelungc = do
  keelungcExists <- checkCmd "keelungc"
  if keelungcExists
    then return $ Just ("keelungc", [])
    else do
      dockerExists <- checkCmd "docker"
      if dockerExists
        then -- insert "--platform=linux/amd64" when we are not on a x86 machine
        case System.Info.arch of
          "x86_64" -> return $ Just ("docker", ["run", "-i", "banacorn/keelung"])
          _ -> return $ Just ("docker", ["run", "-i", "--platform=linux/amd64", "banacorn/keelung"])
        else return Nothing
  where
    -- decide the command for locating executables
    whichCmd :: String
    whichCmd = case System.Info.os of
      "mingw32" -> "where" -- Windows uses "where"
      _ -> "which" -- Unix uses "which"

    -- check if a command exists
    checkCmd :: String -> IO Bool
    checkCmd cmd =
      catchIOError
        (Process.readProcess whichCmd [cmd] mempty >> return True)
        (\_ -> return False)
