{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeFamilies #-}
module Data.Conduit.Binary
    ( sourceFile
    , sinkFile
    , isolate
    ) where

import Prelude hiding (FilePath)
import System.IO (hClose)
import Filesystem.Path.CurrentOS (FilePath)
import qualified Data.ByteString as S
import qualified Data.ByteString.Lazy as L
import Filesystem (openFile, IOMode (ReadMode, WriteMode))
import Data.Conduit
import Control.Monad.Trans.Resource (with, release)
import Data.Int (Int64)
import Control.Monad.Trans.Class (lift)

sourceFile :: (Base m ~ IO, Resource m)
           => FilePath
           -> SourceM m S.ByteString
sourceFile fp = sourceM
    (with (openFile fp ReadMode) hClose)
    (\(key, _) -> release key)
    (\(_, handle) -> do
        bs <- liftBase $ S.hGetSome handle 4096
        if S.null bs
            then return $ SourceResult StreamClosed []
            else return $ SourceResult StreamOpen [bs])

sinkFile :: (Base m ~ IO, Resource m)
         => FilePath
         -> SinkM S.ByteString m ()
sinkFile fp = sinkM
    (with (openFile fp WriteMode) hClose)
    (\(key, _) -> release key)
    (\(_, handle) bss -> lift $ liftBase (L.hPut handle $ L.fromChunks bss) >> return (SinkResult [] Nothing))
    (\(_, handle) bss -> do
        liftBase $ L.hPut handle $ L.fromChunks bss
        return $ SinkResult [] ())

isolate :: Resource m
        => Int64
        -> ConduitM S.ByteString m S.ByteString
isolate count0 = conduitMState
    count0
    push
    close
  where
    push 0 bss = return (0, ConduitResult StreamClosed bss [])
    push count bss = do
        let (a, b) = L.splitAt count $ L.fromChunks bss
        let count' = count - L.length a
        return (count', ConduitResult StreamOpen (L.toChunks b) (L.toChunks a))
    close count bss = do
        let (a, b) = L.splitAt count $ L.fromChunks bss
        return $ ConduitCloseResult (L.toChunks b) (L.toChunks a)