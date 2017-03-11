{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE BangPatterns #-}

module Main (main) where

import           Control.DeepSeq
import           Control.Exception (evaluate)
import           Control.Monad
import           Criterion.Main
import           Criterion.Types
import qualified Data.List as L
import qualified Data.Sequence as S
import qualified Data.Vector as V
import qualified Data.Vector.Unboxed as UV
import           System.Directory

data Conser = forall f. NFData (f Int) => Conser String (Int -> f Int)
data Replicator = forall f. NFData (f Int) => Replicator String (Int -> Int -> f Int)
data Indexing = forall f. NFData (f Int) => Indexing String (IO (f Int)) (f Int -> Int -> Int)
data Length = forall f. NFData (f Int) => Length String (IO (f Int)) (f Int -> Int)
data Min = forall f. NFData (f Int) => Min String (IO (f Int)) (f Int -> Int)
data Max = forall f. NFData (f Int) => Max String (IO (f Int)) (f Int -> Int)
data Sort = forall f. NFData (f Int) => Sort String (IO (f Int)) (f Int -> f Int)
data RemoveElement = forall f. NFData (f Int) => RemoveElement String (IO (f Int)) ((Int -> Bool) -> f Int -> f Int)
data RemoveByIndex = forall f. NFData (f Int) => RemoveByIndex String (IO (f Int)) ((Int -> Int -> Bool) -> f Int -> f Int)

main :: IO ()
main = do
  let fp = "out.csv"
  exists <- doesFileExist fp
  when exists (removeFile fp)
  defaultMainWith
    defaultConfig
    {csvFile = Just fp, regressions = [(["regress"], "allocated:iters")]}
    [ bgroup
        "Consing"
        (conses
           [ Conser "Data.List" conslist
           , Conser "Data.Vector" consvector
           , Conser "Data.Vector.Unboxed" consuvector
           , Conser "Data.Sequence" consseq
           ])
    , bgroup
        "Replicate"
        (replicators
           [ Replicator "Data.List" L.replicate
           , Replicator "Data.Vector" V.replicate
           , Replicator "Data.Vector.Unboxed" UV.replicate
           , Replicator "Data.Sequence" S.replicate
           ])
    , bgroup
        "Indexing"
        (indexes
           [ Indexing "Data.List" sampleList (L.!!)
           , Indexing "Data.Vector" sampleVector (V.!)
           , Indexing "Data.Vector.Unboxed" sampleUVVector (UV.!)
           , Indexing "Data.Sequence" sampleSeq (S.index)
           ])
    , bgroup
        "Length"
        (lengths
           [ Length "Data.List" sampleList (L.length)
           , Length "Data.Vector" sampleVector (V.length)
           , Length "Data.Vector.Unboxed" sampleUVVector (UV.length)
           , Length "Data.Sequence" sampleSeq (S.length)
           ])
    , bgroup
        "Min"
        (mins
           [ Min "Data.List" sampleList (L.minimum)
           , Min "Data.Vector" sampleVector (V.minimum)
           , Min "Data.Vector.Unboxed" sampleUVVector (UV.minimum)
           ])
    , bgroup
        "Max"
        (maxs
           [ Max "Data.List" sampleList (L.maximum)
           , Max "Data.Vector" sampleVector (V.maximum)
           , Max "Data.Vector.Unboxed" sampleUVVector (UV.maximum)
           ])
    , bgroup
        "Sort"
        (sorts
           [ Sort "Data.List" sampleList (L.sort)
           , Sort "Data.Sequence" sampleSeq (S.sort)
           ])
    , bgroup
        "Remove Element"
        (removeElems
           [ RemoveElement "Data.List" sampleList (L.filter)
           , RemoveElement "Data.Vector" sampleVector (V.filter)
           , RemoveElement "Data.Vector.Unboxed" sampleUVVector (UV.filter)
           , RemoveElement "Data.Sequence" sampleSeq (S.filter)
           ])
    , bgroup
        "Remove By Index"
        (removeByIndexes
           [ RemoveByIndex "Data.Vector" sampleVector (V.ifilter)
           , RemoveByIndex "Data.Vector.Unboxed" sampleUVVector (UV.ifilter)
           ])
    ]
  where
    conses funcs =
      [ bench (title ++ ":" ++ show i) $ nf func i
      | i <- [10, 100, 1000, 10000]
      , Conser title func <- funcs
      ]
    replicators funcs =
      [ bench (title ++ ":" ++ show i) $ nf (\(x, y) -> func x y) (i, 1234)
      | i <- [10, 100, 1000, 10000]
      , Replicator title func <- funcs
      ]
    indexes funcs =
      [ env
        payload
        (\p -> bench (title ++ ":" ++ show index) $ nf (\x -> func p x) index)
      | index <- [10, 100, 1000, 10000]
      , Indexing title payload func <- funcs
      ]
    lengths funcs =
      [ env payload (\p -> bench (title ++ ":10000") $ nf (\x -> func x) p)
      | Length title payload func <- funcs
      ]
    mins funcs =
      [ env payload (\p -> bench (title ++ ":10000") $ nf (\x -> func x) p)
      | Min title payload func <- funcs
      ]
    maxs funcs =
      [ env payload (\p -> bench (title ++ ":10000") $ nf (\x -> func x) p)
      | Max title payload func <- funcs
      ]
    sorts funcs =
      [ env payload (\p -> bench (title ++ ":10000") $ nf (\x -> func x) p)
      | Sort title payload func <- funcs
      ]
    removeElems funcs =
      [ env
        payload
        (\p ->
           bench (title ++ ":" ++ show relem) $ nf (\x -> func (/= relem) x) p)
      | relem <- [1, 100, 1000, 10000 :: Int]
      , RemoveElement title payload func <- funcs
      ]
    removeByIndexes funcs =
      [ env
        payload
        (\p ->
           bench (title ++ ":" ++ show relem) $
           nf (\x -> func (\index _ -> index /= relem) x) p)
      | relem <- [1, 100, 1000, 10000 :: Int]
      , RemoveByIndex title payload func <- funcs
      ]

sampleList :: IO [Int]
sampleList = evaluate $ force [1 .. 10005]

sampleVector :: IO (V.Vector Int)
sampleVector = evaluate $ force $ V.generate 10005 id

sampleUVVector :: IO (UV.Vector Int)
sampleUVVector = evaluate $ force $ UV.generate 10005 id

sampleSeq :: IO (S.Seq Int)
sampleSeq = evaluate $ force $ S.fromList [1 .. 10005]

conslist :: Int -> [Int]
conslist n0 = go n0 []
  where go 0 acc = acc
        go n !acc = go (n - 1) (n : acc)

consvector :: Int -> V.Vector Int
consvector n0 = go n0 V.empty
  where go 0 acc = acc
        go n !acc = go (n - 1) (V.cons n acc)

consuvector :: Int -> UV.Vector Int
consuvector n0 = go n0 UV.empty
  where go 0 acc = acc
        go n !acc = go (n - 1) (UV.cons n acc)

consseq :: Int -> S.Seq Int
consseq n0 = go n0 S.empty
  where go 0 acc = acc
        go n !acc = go (n - 1) (n S.<| acc)
