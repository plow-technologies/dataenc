-- |
-- Module    : Codec.Binary.Base32
-- Copyright : (c) 2007 Magnus Therning
-- License   : BSD3
--
-- Implemented as specified in RFC 4648
-- (<http://tools.ietf.org/html/rfc4648>).
--
-- Further documentation and information can be found at
-- <http://www.haskell.org/haskellwiki/Library/Data_encoding>.
module Codec.Binary.Base32
    ( EncIncData(..)
    , EncIncRes(..)
    , encodeInc
    , encode
    , DecIncData(..)
    , DecIncRes(..)
    , decodeInc
    , decode
    , chop
    , unchop
    ) where

import Codec.Binary.Util

import Control.Monad
import Data.Array
import Data.Bits
import Data.Maybe
import Data.Word
import qualified Data.Map as M

-- {{{1 enc/dec map
_encMap =
    [ (0, 'A'), (1, 'B'), (2, 'C'), (3, 'D'), (4, 'E')
    , (5, 'F'), (6, 'G'), (7, 'H'), (8, 'I'), (9, 'J')
    , (10, 'K'), (11, 'L'), (12, 'M'), (13, 'N'), (14, 'O')
    , (15, 'P'), (16, 'Q'), (17, 'R'), (18, 'S'), (19, 'T')
    , (20, 'U'), (21, 'V'), (22, 'W'), (23, 'X'), (24, 'Y')
    , (25, 'Z'), (26, '2'), (27, '3'), (28, '4'), (29, '5')
    , (30, '6'), (31, '7') ]

-- {{{1 encodeArray
encodeArray :: Array Word8 Char
encodeArray = array (0, 32) _encMap

-- {{{1 decodeMap
decodeMap :: M.Map Char Word8
decodeMap = M.fromList [(snd i, fst i) | i <- _encMap]

-- {{{1 encode
-- | Incremental encoder function.
encodeInc :: EncIncData -> EncIncRes String
encodeInc e = eI [] e
    where
        enc5 [o1, o2, o3, o4, o5] = map (encodeArray !) [i1, i2, i3, i4, i5, i6, i7, i8]
            where
                i1 = o1 `shiftR` 3
                i2 = (o1 `shiftL` 2 .|. o2 `shiftR` 6) .&. 0x1f
                i3 = o2 `shiftR` 1 .&. 0x1f
                i4 = (o2 `shiftL` 4 .|. o3 `shiftR` 4) .&. 0x1f
                i5 = (o3 `shiftL` 1 .|. o4 `shiftR` 7) .&. 0x1f
                i6 = o4 `shiftR` 2 .&. 0x1f
                i7 = (o4 `shiftL` 3 .|. o5 `shiftR` 5) .&. 0x1f
                i8 = o5 .&. 0x1f

        eI [] EDone = EFinal []
        eI [o1] EDone = EFinal (take 2 cs ++ "======")
            where
                cs = enc5 [o1, 0, 0, 0, 0]
        eI [o1, o2] EDone = EFinal (take 4 cs ++ "====")
            where
                cs = enc5 [o1, o2, 0, 0, 0]
        eI [o1, o2, o3] EDone = EFinal (take 5 cs ++ "===")
            where
                cs = enc5 [o1, o2, o3, 0, 0]
        eI [o1, o2, o3, o4] EDone = EFinal (take 7 cs ++ "=")
            where
                cs = enc5 [o1, o2, o3, o4, 0]
        eI lo (EChunk bs) = doEnc [] (lo ++ bs)
            where
                doEnc acc (o1:o2:o3:o4:o5:os) = doEnc (acc ++ enc5 [o1, o2, o3, o4, o5]) os
                doEnc acc os = EPart acc (eI os)

-- | Encode data.
encode :: [Word8] -> String
encode = encoder encodeInc

-- {{{1 decode
-- | Incremental decoder function.
decodeInc :: DecIncData String -> DecIncRes String
decodeInc d = dI [] d
    where
        dec8 cs = let
                ds = map (flip M.lookup decodeMap) cs
                es@[e1, e2, e3, e4, e5, e6, e7, e8] = map fromJust ds
                o1 = e1 `shiftL` 3 .|. e2 `shiftR` 2
                o2 = e2 `shiftL` 6 .|. e3 `shiftL` 1 .|. e4 `shiftR` 4
                o3 = e4 `shiftL` 4 .|. e5 `shiftR` 1
                o4 = e5 `shiftL` 7 .|. e6 `shiftL` 2 .|. e7 `shiftR` 3
                o5 = e7 `shiftL` 5 .|. e8
                allJust = and . map isJust
            in if allJust ds
                then Just [o1, o2, o3, o4, o5]
                else Nothing

        dI [] DDone = DFinal [] []
        dI lo DDone = DFail [] lo
        dI lo (DChunk s) = doDec [] (lo ++ s)
            where
                doDec acc s@(c1:c2:'=':'=':'=':'=':'=':'=':cs) = maybe
                    (DFail acc s)
                    (\ bs -> DFinal (acc ++ take 1 bs) cs)
                    (dec8 [c1, c2, 'A', 'A', 'A', 'A', 'A', 'A'])
                doDec acc s@(c1:c2:c3:c4:'=':'=':'=':'=':cs) = maybe
                    (DFail acc s)
                    (\ bs -> DFinal (acc ++ take 2 bs) cs)
                    (dec8 [c1, c2, c3, c4, 'A', 'A', 'A', 'A'])
                doDec acc s@(c1:c2:c3:c4:c5:'=':'=':'=':cs) = maybe
                    (DFail acc s)
                    (\ bs -> DFinal (acc ++ take 3 bs) cs)
                    (dec8 [c1, c2, c3, c4, c5, 'A', 'A', 'A'])
                doDec acc s@(c1:c2:c3:c4:c5:c6:c7:'=':cs) = maybe
                    (DFail acc s)
                    (\ bs -> DFinal (acc ++ take 4 bs) cs)
                    (dec8 [c1, c2, c3, c4, c5, c6, c7, 'A'])
                doDec acc s@(c1:c2:c3:c4:c5:c6:c7:c8:cs) = maybe
                    (DFail acc s)
                    (\ bs -> doDec (acc ++ bs) cs)
                    (dec8 [c1, c2, c3, c4, c5, c6, c7, c8])
                doDec acc s = DPart acc (dI s)

-- | Decode data.
decode :: String
    -> Maybe [Word8]
decode = decoder decodeInc

-- {{{1 chop
-- | Chop up a string in parts.
--
--   The length given is rounded down to the nearest multiple of 8.
chop :: Int     -- ^ length of individual lines
    -> String
    -> [String]
chop n "" = []
chop n s = let
        enc_len | n < 8 = 8
                | otherwise = n `div` 8 * 8
    in take enc_len s : chop n (drop enc_len s)

-- {{{1 unchop
-- | Concatenate the strings into one long string.
unchop :: [String]
    -> String
unchop = foldr (++) ""
