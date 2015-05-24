-- | Parser for .prof files generated by GHC.
module ProfFile
  ( Time(..)
  , Line(..)
  , lIndividualTime
  , lInheritedTime
  , lIndividualAlloc
  , lInheritedAlloc

  , parse

  , processLines
  , findStart
  ) where

import           Control.Arrow (second)
import           Data.Char (isSpace)
import           Text.Read (readEither)
import           Control.Monad (unless)
import           Control.Applicative
import           Prelude -- Quash AMP related warnings in GHC>=7.10

data Time = Time
  { tIndividual :: Double
  , tInherited :: Double
  } deriving (Show, Eq)

data Line = Line
  { lCostCentre :: String
  , lModule :: String
  , lNumber :: Int
  , lEntries :: Int
  , lTime :: Time
  , lAlloc :: Time
  , lChildren :: [Line]
  } deriving (Show, Eq)

lIndividualTime :: Line -> Double
lIndividualTime = tIndividual . lTime

lInheritedTime :: Line -> Double
lInheritedTime = tInherited . lTime

lIndividualAlloc :: Line -> Double
lIndividualAlloc = tIndividual . lAlloc

lInheritedAlloc :: Line -> Double
lInheritedAlloc = tInherited . lAlloc

-- | Returns a function accepting the children and returning a fully
-- formed 'Line'.
parseLine :: String -> Either String ([Line] -> Line)
parseLine s = case words s of
  [costCentre, module_, no, entries, indTime, indAlloc, inhTime, inhAlloc] -> do
    pNo <- readEither no
    pEntries <- readEither entries
    pTime <- Time <$> readEither indTime <*> readEither inhTime
    pAlloc <- Time <$> readEither indAlloc <*> readEither inhAlloc
    return $ Line costCentre module_ pNo pEntries pTime pAlloc
  _ ->
    Left $ "Malformed .prof file line:\n" ++ s

processLines :: [String] -> Either String [Line]
processLines lines0 = do
  (ss, lines') <- go 0 lines0
  unless (null ss) $
    error "processLines: the impossible happened, not all strings were consumed."
  return lines'
  where
    go :: Int -> [String] -> Either String ([String], [Line])
    go _depth [] = do
      return ([], [])
    go depth0 (line : lines') = do
      let (spaces, rest) = break (not . isSpace) line
      let depth = length spaces
      if depth < depth0
        then return (line : lines', [])
        else do
          parsedLine <- parseLine rest
          (lines'', children) <- go (depth + 1) lines'
          second (parsedLine children :) <$> go depth lines''

firstLine :: [String]
firstLine = ["COST", "CENTRE", "MODULE", "no.", "entries", "%time", "%alloc", "%time", "%alloc"]

findStart :: [String] -> Either String [String]
findStart [] = Left "Malformed .prof file: couldn't find start line"
findStart (line : _empty : lines') | words line == firstLine = return lines'
findStart (_line : lines') = findStart lines'

parse :: String -> Either String [Line]
parse s = do
  ss <- findStart $ lines s
  processLines ss
