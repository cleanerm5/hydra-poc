{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}

module Test.EndToEndSpec where

import Cardano.Prelude
import qualified Data.ByteString as BS
import Data.String (String)
import HydraNode (
  failAfter,
  getMetrics,
  hydraNodeProcess,
  readCreateProcess,
  sendRequest,
  waitForNodesConnected,
  waitForResponse,
  withHydraNode,
  withMockChain,
 )
import Test.Hspec (
  Spec,
  describe,
  it,
  shouldSatisfy,
 )
import Text.Regex.TDFA
import Text.Regex.TDFA.Text ()

spec :: Spec
spec = describe "End-to-end test using a mocked chain though" $ do
  describe "three hydra nodes scenario" $ do
    it "inits and closes a head with a single mock transaction" $ do
      failAfter 30 $
        withMockChain $
          withHydraNode 1 $ \n1 ->
            withHydraNode 2 $ \n2 ->
              withHydraNode 3 $ \n3 -> do
                waitForNodesConnected [1, 2, 3] [n1, n2, n3]
                let contestationPeriod = 3 -- TODO: Should be part of init
                sendRequest n1 "Init [1, 2, 3]"
                waitForResponse 3 [n1, n2, n3] "ReadyToCommit"
                sendRequest n1 "Commit 10"
                sendRequest n2 "Commit 20"
                sendRequest n3 "Commit 5"
                -- NOTE(SN): uses MockTx and its UTxO type [MockTx]
                waitForResponse 3 [n1, n2, n3] "HeadIsOpen []"
                sendRequest n1 "NewTx (ValidTx 42)"
                waitForResponse 10 [n1, n2, n3] "TxConfirmed (ValidTx 42)"
                sendRequest n1 "Close"
                waitForResponse 3 [n1] "HeadIsClosed 3s [] 0 [ValidTx 42]"
                waitForResponse (contestationPeriod + 3) [n1] "HeadIsFinalized [ValidTx 42]"

    -- NOTE(SN): This is likely too detailed and should move to a lower-level
    -- integration test
    it "init a head and reject too expensive tx" $ do
      failAfter 30 $
        withMockChain $
          withHydraNode 1 $ \n1 ->
            withHydraNode 2 $ \n2 ->
              withHydraNode 3 $ \n3 -> do
                waitForNodesConnected [1, 2, 3] [n1, n2, n3]
                sendRequest n1 "Init [1, 2, 3]"
                waitForResponse 3 [n1, n2, n3] "ReadyToCommit"
                sendRequest n1 "Commit 10"
                sendRequest n2 "Commit 20"
                sendRequest n3 "Commit 5"
                waitForResponse 3 [n1, n2, n3] "HeadIsOpen []"
                -- NOTE(SN): Everything above this boilerplate
                sendRequest n1 "NewTx InvalidTx"

                waitForResponse 3 [n1] "TxInvalid InvalidTx"

  describe "Monitoring" $ do
    it "Node exposes Prometheus metrics on port 6001" $ do
      failAfter 20 $
        withMockChain $
          withHydraNode 1 $ \n1 -> do
            withHydraNode 2 $ \_ ->
              withHydraNode 3 $ \_ -> do
                waitForNodesConnected [1, 2, 3] [n1]
                sendRequest n1 "Init [1, 2, 3]"
                waitForResponse 3 [n1] "ReadyToCommit"

                metrics <- getMetrics n1
                metrics `shouldSatisfy` ("hydra_head_events  5" `BS.isInfixOf`)

  describe "hydra-node executable" $ do
    it "display proper semantic version given it is passed --version argument" $ do
      failAfter 5 $ do
        version <- readCreateProcess (hydraNodeProcess ["--version"]) ""
        version `shouldSatisfy` (=~ ("[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9]+)?" :: String))
