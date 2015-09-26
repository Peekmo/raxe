package raxe;

class CoreTranspiler implements Transpiler {
  public function new() {}

  public function tokens() : Array<String> {
    return [
      // Standard keywords
      "\"", "\\\"", "(", ")", "/", "=", "#", ",", "@",

      // Raxe keywords
      "-", "require", "def", "self.new", ".new", "self.", "self", "end", "do",

      // Haxe keywords
      "using", "extends", "implements", "inline", "typedef", //"//", "import", "var", "function",

      // Expressions
      "elsif", "if", "else", "while", "for",

      // Types
      "class", "enum", "abstract", "interface",

      // Access modifiers
      "private", "public", "static"
    ];
  }

  public function transpile(handle : StringHandle, packagepath : String, name : String) {
    var alreadyDefined = false;
    handle.insert("package " + packagepath + ";using Lambda;").increment();

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
      else if (handle.is("#") || handle.is("@")) {
        handle.next("\n");
      }
      // Step over things in strings (" ") and process multiline strings
      else if (handle.is("\"")) {
        if (handle.at("\"\"\"")) {
          handle.remove("\"\"\"");
          handle.insert("\"");
        }

        handle.increment();

        while (handle.nextToken()) {
          if (handle.is("#")) {
            handle.remove();
            handle.insert("$");
            handle.increment();
          } else if (handle.is("\"")) {
            break;
          } else {
            handle.increment();
          }
        }

        if (handle.at("\"\"\"")) {
          handle.remove("\"\"\"");
          handle.insert("\"");
        }

        handle.increment();
      }
      else if (handle.is("self.new")) {
        handle.remove();
        handle.insert("new " + name);
        handle.increment();
      }
      else if (handle.is(".new")) {
        handle.remove();
        handle.prevTokenLine();
        handle.increment();
        handle.insert("new ");
        handle.increment();
      }
      // Change end to classic bracket end
      else if (handle.safeis("end")) {
        handle.remove();
        handle.insert("}");
        handle.increment();
      }
      // Change require to classic imports
      else if (handle.safeis("require")) {
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
      else if (handle.safeis("def")) {
        handle.remove("def");
        var position = handle.position;
        handle.nextToken();

        if (handle.safeisStart("self.")) {
          handle.remove();
          handle.position = position;
          handle.insert("static ");
          handle.increment();
          position = handle.position;
        }

        handle.nextToken();

        if (handle.is("(")) {
          handle.position = position;
          handle.insert("function");
          consumeCurlys(handle);
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
      else if (handle.safeis("do")) {
        handle.remove("do");
        handle.insert("function");
        consumeCurlys(handle);
        handle.insert("{");
        handle.increment();
      }
      // Insert begin bracket after if and while
      else if (handle.safeis("if") || handle.safeis("while") || handle.safeis("for")) {
        handle.increment();
        consumeCurlys(handle);
        handle.insert("{");
        handle.increment();
      }
      // Change elseif to else if and insert begin and end brackets around it
      else if (handle.safeis("elsif")) {
        handle.remove();
        handle.insert("}else if");
        handle.increment();
        consumeCurlys(handle);
        handle.insert("{");
        handle.increment();
      }
      else if (handle.safeis("next")) {
        handle.remove();
        handle.insert("continue");
        handle.increment();
      }
      // Inser begin and end brackets around else but do not try to
      // process curlys because there will not be any
      else if (handle.safeis("else")) {
        handle.insert("}");
        handle.increment();
        handle.increment("else");
        handle.insert("{");
        handle.increment();
      }
      // Process module declarations and insert curly after them
      else if (handle.safeis("self")) {
        handle.remove();

        if (!alreadyDefined) {
          while(handle.nextToken()) {
           if (handle.is("enum") ||
                handle.is("class") ||
                handle.is("abstract") ||
                handle.is("interface")) {
              handle.increment();
              handle.insert(" " + name + " ");
              handle.next("\n");
              handle.insert("{");
              handle.increment();
              alreadyDefined = true;
              break;
            }
          }
        } else {
          handle.insert(name);
        }
      }
      else if (handle.safeisStart("self.")) {
        handle.remove();
        handle.insert(name + ".");
        handle.increment();
      }
      else {
        handle.increment(); // Skip this token
      }
    }

    return handle.content + "}";
  }

  private function consumeCurlys(handle : StringHandle) {
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