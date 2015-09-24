package raxe;

import sys.FileSystem;
import sys.io.File;

class Transpiler {
  var currentPackage : String;
  var currentModule : String;
  var inputFile : String;
  var outputFile : String;
  var handle : StringHandle;

  var tokens = [
    // Standard keywords
    "\"", "\\\"", "(", ")", "/", "=", "#",

    // Raxe keywords
    "-", "require", "module", "def", "end", "do",

    // Haxe keywords
    "using", "extends", "implements", "inline", "typedef", //"//", "import", "var", "function",

    // Expressions
    "if", "else", "case", "elseif", "while",

    // Types
    "class", "enum", "abstract",

    // Access modifiers
    "private", "public", "static"
  ];

  var public_tokens = [
    "{", "}", "[", "]", "(", ")",
    "//", "/*", "*/", "\"", "\\\"",
    "var", "function", "public"
  ];

  var semicolon_tokens = [
    "{", "}", "[", "]", "(", ")", ",", ":",
    "//", "/*", "*/", "\"", "\\\"", "=",
    "break", "continue", "return"
  ];
  
  public function new(directory : String, inputFile : String, outputFile : String) {
    this.inputFile = inputFile;
    this.outputFile = outputFile;

    currentPackage = StringTools.replace(inputFile, directory, "");
    currentPackage = StringTools.replace(currentPackage, "\\", "/");
    currentModule = StringTools.replace(currentPackage.substr(currentPackage.lastIndexOf("/") + 1), ".rx", "");
    currentPackage = StringTools.replace(currentPackage, currentPackage.substr(currentPackage.lastIndexOf("/")), "");
    currentPackage = StringTools.replace(currentPackage, "/", ".");

    handle = new StringHandle(File.getContent(inputFile), tokens);
  }

  public function save() {
    File.saveContent(outputFile, handle.content);
  }

  public function transpile() {
    handle.insert("package " + currentPackage + ";using Lambda;").increment();

    while (handle.nextToken()) {
      // Process comments and ignore everything in
      // them until end of line or until next match if multiline
      if (handle.is("-")) {
        var comment = "";
        var position = handle.position;

        while(handle.nextTokenLine()) {
          handle.increment(); 

          if (handle.is("-")) {
            comment += "-";
          } else {
            break;
          }
        }

        handle.position = position;
        handle.current = "-";

        if (comment.length > 2) {
          handle.remove(comment);
          handle.insert("/* ");
          handle.increment();
          handle.next(comment);
          handle.remove(comment);
          handle.insert(" */");
          handle.increment();
        } else if (comment.length == 2) {
          handle.remove(comment);
          handle.insert("//");
          handle.increment();
          handle.next("\n");
          handle.increment();
        } else {
          handle.increment();
        }
      }
      // Skip compiler defines
      else if (handle.is("#")) {
        handle.next("\n");
      }
      // Step over things in strings (" ") and process multiline strings
      else if (handle.is("\"")) {
        if (handle.at("\"\"\"")) {
          handle.remove("\"\"");
        }

        handle.increment();
        handle.next("\"");

        if (handle.at("\"\"\"")) {
          handle.remove("\"\"");
        }

        handle.increment();
      }
      // Change end to classic bracket end
      else if (handle.is("end")) {
        handle.remove();
        handle.insert("}");
        handle.increment();
      }
      // Change require to classic imports
      else if (handle.is("require")) {
        handle.remove();
        handle.insert("import");
        handle.increment();

        var firstQuote = true;

        while (handle.nextToken()) {
          if (handle.is("\"")) {
            handle.remove();

            if (!firstQuote) {
              handle.insert(";");
              handle.increment();
              break;
            }

            firstQuote = false;
          } else if (handle.is("/")) {
            handle.remove();
            handle.insert(".");
          }

          handle.increment();
        }
      }
      // Defines to variables and functions
      else if (handle.is("def")) {
        handle.remove("def");
        var position = handle.position;
        handle.nextToken();

        if (handle.is("(")) {
          handle.position = position;
          handle.insert("function");
          consumeCurlys();
          handle.next("\n");
          handle.insert("{");
          handle.increment();
        } else {
          handle.position = position;
          handle.insert("var");
          handle.increment();
        }
      }
      // Defines to variables and functions
      else if (handle.is("do")) {
        handle.remove("do");
        handle.insert("function");
        consumeCurlys();
        handle.insert("{");
        handle.increment();
      }
      // Insert begin bracket after if and while
      else if (handle.is("if") || handle.is("while")) {
        handle.increment();
        consumeCurlys();
        handle.insert("{");
        handle.increment();
      }
      // Change elseif to else if and insert begin and end brackets around it
      else if (handle.is("elseif")) {
        handle.remove();
        handle.insert("}else if");
        handle.increment();
        consumeCurlys();
        handle.insert("{");
        handle.increment();
      }
      // Inser begin and end brackets around else but do not try to
      // process curlys because there will not be any
      else if (handle.is("else")) {
        handle.insert("}");
        handle.increment();
        handle.increment("else");
        handle.insert("{");
        handle.increment();
      }
      // Process module declarations and insert curly after them
      else if (handle.is("module")) {
        handle.remove();

        while(handle.nextToken()) {
          if (handle.is("enum") ||
              handle.is("class") ||
              handle.is("abstract")) {
            handle.increment();
            handle.insert(" " + currentModule + " ");
            handle.increment();
          } else if (handle.is("extends") || handle.is("implements")) {
            handle.increment();
          } else {
            handle.insert("{");
            handle.increment();
            break;
          }
        }
      }
      else {
        handle.increment(); // Skip this token
      }
    }

    handle.content = handle.content + "}";
    transpilePublic();
    transpileSemicolons();

    return this;
  }

  private function transpilePublic() {
    handle = new StringHandle(handle.content, public_tokens);
    var count = -1;
    var alreadyPublic = false;

    while(handle.nextToken()) {
      if (handle.is("\"")) {
        handle.increment();
        handle.next("\"");
        handle.increment();
      } else if (handle.is("//")) {
        handle.increment();
        handle.next("\n");
        handle.increment();
      } else if (handle.is("/*")) {
        handle.increment();
        handle.next("*/");
        handle.increment();
      } else if (handle.is("[") || handle.is("{")) {
        count++;
        handle.increment();
      } else if (handle.is("]") || handle.is("}")) {
        count--;
        handle.increment();
      } else if (handle.is("public")) {
        alreadyPublic = true;
        handle.increment();
      } else if (handle.is("var") || handle.is("function")) {
        var current = handle.current;

        if (count == 0 && !alreadyPublic) {
          handle.insert("public ");
          handle.increment();
        }
        
        alreadyPublic = false;
        handle.increment(current);
      } else {
        handle.increment();
      }
    }
  }

  private function transpileSemicolons() {
    handle = new StringHandle(handle.content, semicolon_tokens);
    var last = "";

    while(handle.nextTokenLine()) {
      if (handle.is("\"")) {
        handle.increment();
        handle.next("\"");
        last = handle.current;
        handle.increment();
      } else if (handle.is("/*")) {
        handle.increment();
        handle.next("*/");
        handle.increment();
      } else {
        if (handle.is("\n") || handle.is("//")) {
          if (last == "}" || last == "]" || last == ")" || last == "\"" || last == "=" || last == ":" || last == ")" || last == "continue" || last == "break" || last == "return") {
            handle.insert(";");
            handle.increment();
          }

          if (handle.is("//")) {
            handle.increment();
            handle.next("\n");
          } 
        }
        
        last = handle.current;
        handle.increment();
      }
    }
  }

  private function consumeCurlys() {
    var count = 0;

    while(handle.nextToken()) {
      if (handle.is("(")) {
        count++;
      } else if (handle.is(")")) {
        count--;
      }

      handle.increment();
      if (count == 0) break;
    }
  }
}