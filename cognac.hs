-- TODO: Rewrite all of this properly.

{-# LANGUAGE LambdaCase #-}

import System.Process
import System.Environment
import Data.List
import Data.Char
import Data.Ratio
import Data.Maybe
import Control.Exception
import Data.List.Split

replace from to = intercalate to . splitOn from

data Tree =
  Leaf String | Node [Tree]
  deriving (Eq, Show)

parsefile :: String -> [Tree]
-- Let's be honest, most of the parsing functions are obselete now.
parsefile = -- Parsefile takes a string (the file text) as an argument and returns a list of strings (tokens) in the file
  parsesemicolons . -- Reverse sections bounded by semicolons
  parsebrackets . -- Convert bracketed sections to nodes
  map (Leaf . parsenumbers) .
  words . -- Separate into tokens
  parseinformalsyntax .
  map parsesymbols .
  replacesymbols .
  padtokens . -- Space out special characters.
  unwords . parsecomments . splitOn "~" -- When you realise that americans can't type tildas :(
  -- Parse line comments somewhere...
  -- unwords $ parsecharacters $ splitOn "\'" $ -- Convert characters to ASCII value integers
  -- unwords $ parsestrings $ splitOn "\"" -- Convert strings to lists of characters (except i haven't implemented lists yet!)

replacesymbols =
  unwords .
  replace [ "==" ] [ "Equal"          ] .
  replace [ "!=" ] [ "NotEqual"       ] .
  replace [ "<"  ] [ "Preceed"        ] .
  replace [ ">"  ] [ "Exceed"         ] .
  replace [ ">=" ] [ "EqualOrExceed"  ] .
  replace [ "<=" ] [ "EqualOrPreceed" ] .
  replace [ "+"  ] [ "Sum"            ] .
  replace [ "-"  ] [ "Difference"     ] .
  replace [ "*"  ] [ "Product"        ] .
  replace [ "/"  ] [ "Divisor"        ] .
  words


-- Constants!!!
openbrackets  = [ '(' ]
closebrackets = [ ')' ]
delims        = [ ';',','     ]
numbers       =  '.':['0'..'9']
upperletters  = [ 'A'..'Z'    ]
lowerletters  = [ 'a'..'z'    ]
brackets      = openbrackets ++ closebrackets
permittedsymbols = delims    ++ brackets      ++ numbers ++ lowerletters ++ upperletters
formalsymbols = delims       ++ brackets      ++ numbers ++ upperletters

{- parsestrings :: [String] -> [String]
parsestrings (x:y:xs) =
  x : "Tuple" : intercalate " Tuple " (init str) : last str : parsestrings xs
    where str = map (\s -> " \'" ++ [s] ++ "\'") y
parsestrings x = x  -}

{- parsecharacters :: [String] -> [String]
parsecharacters (x:y:xs) =
  x : " Symbol " : show (ord $ head y) : parsecharacters xs
parsecharacters x = x -}

padtokens :: String -> String
padtokens =
  pad (brackets ++ delims)
    where
      pad :: String -> String -> String
      pad (x:xs) str =
        pad xs $
        replace [x] (' ' : x : " ") str
      pad _ x = x

parsesymbols :: Char -> Char
parsesymbols str -- Remove all those pesky symbols.
  | str `elem` permittedsymbols = str
  | otherwise = ' '

parsecomments :: [String] -> [String]
parsecomments (x:y:xs) = x : parsecomments xs
parsecomments x = x

parsenumbers :: String -> String
parsenumbers (x:xs)
  | x `elem` ('-':'.':numbers) = x : filter (`elem` ('.':numbers)) xs
  | otherwise = x : xs

-- <Bodge>
parsebrackets :: [Tree] -> [Tree]

parsebrackets tokens =
  if closepos /= -1 then -- If there are brackets present, convert them to a list and recur.
    parsebrackets
    (take openpos tokens ++
      [Node
        (take (closepos - openpos - 1)
      (drop (openpos + 1) tokens))] ++
        drop (closepos + 1) tokens)
  else tokens

  where
    leaves = -- Tokens without nodes (allowing me to search it like a normal list)
      map -- Map a function that returns leaves but converts nodes to empty strings onto tokens, returning a [String] for easy processing
      (\case
          Leaf y ->
            y
          Node _ ->
            "")
            tokens

    closepos = -- 1st close bracket.
      fromMaybe (-1) (findIndex (`elem` map (:[]) closebrackets) leaves)

    openpos = -- Last open bracket before closepos.
      case findIndex (`elem` map (:[]) openbrackets) (reverse (take closepos leaves)) of
        Just x ->
          closepos - x - 1
        Nothing ->
          -1
-- </bodge> If it ain't broke, don't fix it.

parsesemicolons :: [Tree] -> [Tree]

parsesemicolons =
  map nodes .
  concatMap reverse .
    splitWhen semicolon
  where
    nodes (Node x) = Node $ parsesemicolons x
    nodes       x  = x
    semicolon (Leaf (x:xs)) 
      | x `elem` delims = True
      | otherwise       = False
    semicolon _         = False

parseinformalsyntax :: String -> String
parseinformalsyntax =
  unwords . filter isformal . words
    where
      isformal word =
        head word `elem` formalsymbols


compile :: [Tree] -> String

{-
compile (Node body : Node call : Leaf "Alias" : rest) = 
  -- TODO: Fix
  let name = last call
      args = init call in
        compile $ macroexpand name args body rest
          where
            macroexpand :: Tree -> [Tree] -> [Tree] -> [Tree] -> [Tree]
            macroexpand _ _ _ [] = []
            macroexpand name args body (x:xs)
              | (x:xs) !! length args == name = 
                foldl replacemacroarg body (zip call (x:xs))
                  ++ drop (length args) xs
              | otherwise = (case x of Leaf _ -> x
                                       Node y -> Node $ macroexpand name args body y)
                            : macroexpand name args body xs
            replacemacroarg [] (_,_) = []
            replacemacroarg (x : xs) (argname, argvalue)
              | argname == x = argvalue : replacemacroarg xs (argname, argvalue)
              | otherwise = (case x of
                               Leaf _ -> x
                               Node y -> Node $ replacemacroarg y (argname, argvalue)) : replacemacroarg xs (argname, argvalue)

macroreplace :: Tree -> [Tree] -> [Tree] -> [Tree]
macroreplace _ _ [] = []
macroreplace oldtoken newtokens (Node token : oldAST) =
  macroexpand $! Node (macroreplace oldtoken newtokens token) : macroreplace oldtoken newtokens oldAST
macroreplace oldtoken newtokens (token : oldAST)
  | token == oldtoken = macroexpand $! macroreplace oldtoken newtokens newtokens ++ macroreplace oldtoken newtokens oldAST
  | token /= oldtoken = macroexpand $! token : macroreplace oldtoken newtokens oldAST

macroexpand :: [Tree] -> [Tree]
macroexpand (Node expr : Node name_and_args : Leaf "Alias" : oldAST) =
  let name = last name_and_args
      args = reverse $ init name_and_args in
      macroexpand $ macroreplace name (macroexpand (intersperse (Leaf "Alias") args ++ [Leaf "Alias"] ++ expr)) oldAST

macroexpand (Node expr : xs) = Node (macroexpand expr) : xs
macroexpand (expr : Node name_and_args : Leaf "Alias" : oldAST) = macroexpand $ expr : Node name_and_args : Leaf "Alias" : oldAST
macroexpand (expr : name : (Leaf "Alias") : oldAST) = macroexpand $ macroreplace name [expr] oldAST 
macroexpand (x : xs) = x : macroexpand xs
macroexpand [] = []
-}

compile (Node body : Node call : Leaf "Let" : xs) =
  let name = last call
      args = init call in
  "cognate_define(" ++ lc 
    (case name of 
      Leaf str -> str
      _        -> error "Invalid function name!") ++ ", {\n"
  ++ compile (intersperse (Leaf "Let") (reverse args) ++ [Leaf "Let" | not (null args)] ++ body)
  ++ "});\n{\n"
  ++ compile xs ++
  "}\n"

-- Bind is more elegant, but cannot reccur. Maybe a compromise, where the function is defined at the start of the current block.
{- compile (Leaf name : Leaf "Bind" : xs) =
  "void(^cognate_"
  ++ lc name
  ++ ")(void)=pop(block);"
  ++ compile xs -}

compile (Leaf name : Leaf "Let" : xs) =
  -- Define a temporary variable. Then define a function that pushes that variable to the stack. Bit of a bodge, hopefully clang fixes it.
  "cognate_let(" ++ lc name ++ ");\n{\n"
  ++ compile xs ++ "}\n"

{- compile (Leaf name : Leaf "Set" : xs) =
  -- Todo. Put macro over this like i did with let.
  "temp_"
  ++ lc name
  ++ "=pop_object();cognate_"
  ++ lc name
  ++ "=^{push_object(temp_"
  ++ lc name ++ ");};"
  ++ compile xs -}

-- Primitive Do inlining.
compile (Node expr : Leaf "Do" : xs) =
  "{\n" ++
    compile expr ++
  "}\n" ++
  compile xs

compile (Node expr : xs) =
  "push(block,\n^{\n"
  ++ compile expr
  ++ "});\n"
  ++ compile xs

compile (Leaf token : xs)
  | all (`elem` ('.':'-':['0'..'9'])) token = "push(number," ++ token ++ ");\n" ++ compile xs
--  | null xs = "attempt_tco(" ++ lc token ++ ");\n"
  | otherwise = "call(" ++ lc token ++ ");\n" ++ compile xs

compile [] = ""

compilerFlags = ["-fblocks", "-Wall", "-Wpedantic", "-Wno-unused", "-O3", "-s"]
compiler = "clang"

formatFlags = ["-i"]
formatter = "clang-format"

getPath =
  intercalate "/" . init . splitOn "/" <$> getExecutablePath

main :: IO ()
main =
  do
    path <- getPath
    args <- getArgs
    let compilerFlags = 
          words $ "-fblocks -lBlocksRuntime -l:libgc.a -Wall -Wpedantic -Wno-unused -O3 -s -I " 
          ++ path ++ "/headers" 

    let in_file = head args
    let out_file = head (splitOn "." in_file) ++ ".c"
    let compiler_args = tail args

    putStrLn "  ____                         ____ \n / ___|___   __ _ _ __   __ _ / ___|\n| |   / _ \\ / _` | '_ \\ / _` | |    \n| |__| (_) | (_| | | | | (_| | |___\n \\____\\___/ \\__, |_| |_|\\__,_|\\____|\n            |___/                   "
    putStrLn "Cognate Compiler - Version 0.0.1"
    putStrLn $ "Compiling " ++ in_file ++ " to " ++ out_file ++ "... "
    source <- readFile in_file
    writeFile out_file $ "#include\"cognate.c\"\nint main()\n{\ninit();\n" ++ compile (parsefile source) ++ "return 0;\n}\n"
    rawSystem formatter (formatFlags ++ [out_file])
    putStrLn $ "Compiling " ++ out_file ++ " to " ++ stripExtension in_file ++ "... "
    rawSystem compiler ([out_file, "-o", stripExtension in_file] ++ compilerFlags ++ compiler_args)
    putStrLn "Done!"
    return ()

stripExtension = head . splitOn "."
lc = map toLower
