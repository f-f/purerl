{-# LANGUAGE GADTs #-}

-- |
-- Functions for replacing fully applied type synonyms
--
module Language.PureScript.Erl.Synonyms
  ( SynonymMap
  , replaceRecordRowTypeSynonymsM
  , replaceAllTypeSynonyms'
  ) where

import           Prelude.Compat

import           Control.Monad.Error.Class (MonadError(..))
import           Control.Monad.State
import           Data.Maybe (fromMaybe)
import qualified Data.Map as M
import           Data.Text (Text)
import           Language.PureScript.Environment
import Language.PureScript.Erl.Errors (MultipleErrors, rethrow, rethrowWithPosition, addHint, errorMessage)
import Language.PureScript.Erl.Errors.Types
import           Language.PureScript.Kinds
import           Language.PureScript.Names
import           Language.PureScript.TypeChecker.Monad
import           Language.PureScript.Types

-- | Type synonym information (arguments with kinds, aliased type), indexed by name
type SynonymMap = M.Map (Qualified (ProperName 'TypeName)) ([(Text, Maybe SourceKind)], SourceType)

replaceRecordRowTypeSynonyms'
  :: SynonymMap
  -> SourceType
  -> Either MultipleErrors SourceType
replaceRecordRowTypeSynonyms' syns = everywhereOnTypesTopDownM try
  where
  try :: SourceType -> Either MultipleErrors SourceType
  try t = fromMaybe t <$> go t

  go :: SourceType -> Either MultipleErrors (Maybe SourceType)
  go t@(TypeApp _ tr t1) | tr == tyRecord 
    = Just <$> replaceAllTypeSynonyms' syns t                   
  go tt = return Nothing

replaceAllTypeSynonyms'
  :: SynonymMap
  -> SourceType
  -> Either MultipleErrors SourceType
replaceAllTypeSynonyms' syns = everywhereOnTypesTopDownM try
  where
  try :: SourceType -> Either MultipleErrors SourceType
  try t = fromMaybe t <$> go 0 [] t

  go :: Int -> [SourceType] -> SourceType -> Either MultipleErrors (Maybe SourceType)
  go c args (TypeConstructor _ ctor)
    | Just (synArgs, body) <- M.lookup ctor syns
    , c == length synArgs
    = let repl = replaceAllTypeVars (zip (map fst synArgs) args) body
      in Just <$> try repl
    | Just (synArgs, _) <- M.lookup ctor syns
    , length synArgs > c
    = throwError . errorMessage $ InternalError "Partially applied type synonym"
  go c args (TypeApp _ f arg) = go (c + 1) (arg : args) f
  go _ _ t = return Nothing

-- | Replace fully applied type synonyms by explicitly providing a 'SynonymMap'.
replaceRecordRowTypeSynonymsM
  :: MonadError MultipleErrors m
  => SynonymMap
  -> SourceType
  -> m SourceType
replaceRecordRowTypeSynonymsM syns = either throwError pure . replaceRecordRowTypeSynonyms' syns
