package raxe;

import sys.io.File;
import raxe.cli.Cli;

class Main {
  static function main() {
    new mcli.Dispatch(Sys.args()).dispatch(new Cli());
  }
}
