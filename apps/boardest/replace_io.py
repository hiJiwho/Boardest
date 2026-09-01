import os
import glob

def replace_dart_io():
    base_dir = os.path.abspath('lib')
    dart_files = glob.glob(os.path.join(base_dir, '**', '*.dart'), recursive=True)
    
    count = 0
    for file_path in dart_files:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        if "import 'dart:io';" in content:
            new_content = content.replace("import 'dart:io';", "import 'package:universal_io/io.dart';")
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            count += 1
            print(f"Replaced in {file_path}")
            
    print(f"Total {count} files updated.")

if __name__ == '__main__':
    replace_dart_io()
