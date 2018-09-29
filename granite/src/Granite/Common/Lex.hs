-- |
-- Lexicographical analysis is provided as parsers that parse specific expected
-- tokens, not as a stream of tokens. Tokens already skip whitespace.
--
-- I am aware that having a separate lexer, communicating through a list of
-- tokens, is superior. The problem is that the parser combinator libraries
-- make it a pain to use lists of tokens as inputs to the parsers.
module Granite.Common.Lex
  ( -- * Identifiers
    identifier

    -- * Keywords
  , Keyword (..)
  , keywordSpelling
  , keyword

    -- * Punctuation
  , Punctuation (..)
  , punctuationSpelling
  , punctuation

    -- * Literals
  , textLiteral

    -- * Compound
  , name
  ) where

import Control.Applicative ((<|>), many)
import Control.Monad (when)
import Data.Text (Text)
import Text.Parsec ((<?>))
import Text.Parsec.Text (Parser)

import qualified Text.Parsec as Parser
import qualified Data.Text as Text

import Granite.Common.Name (Infix (..), Name (..))
import Granite.Common.Position (Position (..))

--------------------------------------------------------------------------------
-- Identifiers

-- |
-- Lex an identifier.
identifier :: Parser (Position, Text)
identifier = (<?> "identifier") . Parser.try . lexeme $ do
  ident <- (Text.pack .) . (:) <$> identifierHead <*> Parser.many identifierTail
  when (ident `elem` fmap keywordSpelling [minBound .. maxBound]) $
    Parser.unexpected $ "keyword " ++ show ident
  pure ident

identifierHead :: Parser Char
identifierHead = Parser.oneOf (['a' .. 'z'] ++ ['A' .. 'Z'] ++ "_")

identifierTail :: Parser Char
identifierTail = identifierHead <|> Parser.oneOf (['0' .. '9'] ++ "'!?")

--------------------------------------------------------------------------------
-- Keywords

-- |
-- Keywords.
data Keyword :: * where
  K_forall :: Keyword
  K_foreign :: Keyword
  K_infix :: Keyword
  K_is :: Keyword
  K_lambda :: Keyword
  K_of :: Keyword
  K_value :: Keyword
  deriving stock (Eq, Ord, Bounded, Enum, Show)

-- |
-- Given a keyword, its spelling.
keywordSpelling :: Keyword -> Text
keywordSpelling = Text.pack . drop 2 . show

-- |
-- Lex a keyword.
keyword :: Keyword -> Parser Position
keyword kw = fmap fst . lexeme . Parser.try $
  Parser.string (Text.unpack (keywordSpelling kw))
  <* Parser.notFollowedBy identifierTail

--------------------------------------------------------------------------------
-- Punctuation

-- |
-- Punctuation.
data Punctuation :: * where
  P_hyphen_greater :: Punctuation
  P_paren_left :: Punctuation
  P_paren_right :: Punctuation
  P_period :: Punctuation
  P_semicolon :: Punctuation
  deriving stock (Eq, Ord, Bounded, Enum, Show)

-- |
-- Given punctuation, its spelling.
punctuationSpelling :: Punctuation -> Text
punctuationSpelling P_hyphen_greater = "->"
punctuationSpelling P_paren_left     = "("
punctuationSpelling P_paren_right    = ")"
punctuationSpelling P_period         = "."
punctuationSpelling P_semicolon      = ";"

-- |
-- Lex punctuation.
punctuation :: Punctuation -> Parser Position
punctuation = fmap fst . lexeme . Parser.string . Text.unpack . punctuationSpelling

--------------------------------------------------------------------------------
-- Literals

textLiteral :: Parser (Position, Text)
textLiteral = lexeme $ do
  _ <- Parser.char '"'
  cs <- many (Parser.noneOf ['"'])
  _ <- Parser.char '"'
  pure $ Text.pack cs

--------------------------------------------------------------------------------
-- Compound

-- |
-- Lex a name.
name :: Parser (Position, Name)
name = plainName <|> infixName
  where
  plainName =
    fmap PlainName <$> identifier

  infixName = do
    position <- keyword K_infix
    _ <- punctuation P_hyphen_greater
    pure (position, InfixName InfixHyphenGreater)

--------------------------------------------------------------------------------

lexeme :: Parser a -> Parser (Position, a)
lexeme parser = do
  let space = Parser.oneOf " \t\r\n"
  _ <- many space
  position <- makePosition <$> Parser.getPosition
  result <- parser
  _ <- many space
  pure (position, result)

makePosition :: Parser.SourcePos -> Position
makePosition pos =
  let
    line   = Parser.sourceLine pos
    column = Parser.sourceColumn pos
    file   = Parser.sourceName pos
  in
    Position line column file
