//
//  SourceEditorCommand.swift
//  HYExtension
//
//  Created by 莫名 on 2020/10/12.
//

import Foundation
import XcodeKit

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        
        if invocation.commandIdentifier.contains("GeneratePropertyGetter") {
            handleGeneratePropertyGetter(with: invocation)
        } else if invocation.commandIdentifier.contains("ImportHeader") {
            handleImportHeader(with: invocation)
        }
        completionHandler(nil)
    }
    
}

//MARK: Import Header Extension

extension SourceEditorCommand {
    
    func handleImportHeader(with invocation: XCSourceEditorCommandInvocation) {
        guard let start = (invocation.buffer.selections.firstObject as? XCSourceTextRange)?.start else {
            return
        }
        guard let end = (invocation.buffer.selections.lastObject as? XCSourceTextRange)?.end else {
            return
        }
        guard let lines = invocation.buffer.lines as? Array<String> else {
            return
        }
        
        if start.line != end.line {
            return
        }
        
        let currentLine = lines[start.line]
        let range = NSRange(location: start.column, length: end.column - start.column)
        let headerName = (currentLine as NSString).substring(with: range)
        
        //规则校验
        do {
            let pattern = "^[a-z|A-Z|_](\\w+)$"
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matchs = regex.matches(in: headerName, options: .reportProgress, range: NSRange(location: 0, length: headerName.count))
            if matchs.count == 0 {
                return
            }
            
            //查找插入位置
            var insertTargetLine = NSNotFound
            for (i, line) in lines.enumerated() {
                if line.contains("#import") {
                    if line.contains("\(headerName).h") {
                        return
                    }
                    insertTargetLine = i + 1
                }
                if line.contains("@interface") || line.contains("@implementation") {
                    break
                }
            }
            
            if insertTargetLine != NSNotFound {
                invocation.buffer.lines.insert("#import \"\(headerName).h\"", at: insertTargetLine)
            }
        } catch _ {
            
        }
    }
    
}

//MARK: Generate Property Getter Extesion

extension SourceEditorCommand {
    
    func handleGeneratePropertyGetter(with invocation: XCSourceEditorCommandInvocation) {
        let contentUTI = invocation.buffer.contentUTI
        // 判断是否为OC .m文件，否则不处理
        if contentUTI != "public.objective-c-source" {
            return
        }
        
        let buffer = invocation.buffer
        guard let startLine = (buffer.selections.firstObject as? XCSourceTextRange)?.start.line else {
            return
        }
        guard let endLine = (buffer.selections.lastObject as? XCSourceTextRange)?.end.line else {
            return
        }
        guard let lines = buffer.lines as? Array<String> else {
            return
        }
        
        var insertPropertyGetters = [String]()
        for i in startLine...endLine {
            let line = lines[i]
            
            if line.contains("@property") {
                //解析属性的类名、成员变量名
                if let result = getPropertyClassNameAndIvarName(line) {
                    if let getter = generateGetter(with: result.0, ivarName: result.1) {
                        insertPropertyGetters.append(getter)
                    }
                }
            }
        }
        
        if insertPropertyGetters.count == 0 {
            return
        }
        
        //获取插入位置
        var insertTargetLine = 0
        var findEndLine = false
        for (i, line) in lines.reversed().enumerated() {
            if line.contains("@end") {
                findEndLine = true
                continue
            }
            if findEndLine && line.trimmingCharacters(in: .whitespacesAndNewlines).count > 0 {
                insertTargetLine = lines.count - i + 1
                break
            }
        }
        if insertTargetLine > 0 && insertTargetLine <= lines.count {
            buffer.lines.insert(insertPropertyGetters.joined(), at: insertTargetLine)
        }
    }
    
}

extension SourceEditorCommand {
    
    func getPropertyClassNameAndIvarName(_ line: String) -> (String, String)? {
        if !line.contains("@property") {
            return nil
        }
        let range = (line as NSString).range(of: ")")
        let subFromIndex = range.location == NSNotFound ? "@property".count : range.location + 1
        var substring = (line as NSString).substring(from: subFromIndex)
        substring = substring.replacingOccurrences(of: ";", with: "")
        substring = substring.replacingOccurrences(of: "\n", with: "")
        substring = substring.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !substring.contains("*") {
            return nil
        }
        
        let results = substring.components(separatedBy: "*")
        if results.count != 2 {
            return nil
        }
        let className = results.first!.replacingOccurrences(of: " ", with: "")
        let ivarName = results.last!.replacingOccurrences(of: " ", with: "")
        return (className, ivarName)
    }
    
}

extension SourceEditorCommand {
    
    func generateGetter(with className: String, ivarName: String) -> String? {
        switch className {
        case "UIImageView":
            return UIImageViewGetter(ivarName)
        case "UILabel":
            return UILabelGetter(ivarName)
        case "UIButton":
            return UIButtonGetter(ivarName)
        default:
            return CommonGetter(className, ivarName)
        }
    }
    
    func UIImageViewGetter(_ ivarName: String) -> String {
        return """
        - (UIImageView *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[UIImageView alloc] init];
                _\(ivarName).image = [UIImage imageNamed:@""];
            }
            return _\(ivarName);
        }
        \n
        """
    }
    
    func UIButtonGetter(_ ivarName: String) -> String {
        return """
        - (UIButton *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[UIButton alloc] init];
                _\(ivarName).titleLabel.font = [UIFont systemFontOfSize:16];
                [_\(ivarName) setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
                [_\(ivarName) setImage:[UIImage imageNamed:@""] forState:UIControlStateNormal];
                [_\(ivarName) setTitle:@"" forState:UIControlStateNormal];
            }
            return _\(ivarName);
        }
        \n
        """
    }

    func UILabelGetter(_ ivarName: String) -> String {
        return """
        - (UILabel *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[UILabel alloc] init];
                _\(ivarName).font = [UIFont systemFontOfSize:16];
                _\(ivarName).textColor = [UIColor blackColor];
            }
            return _\(ivarName);
        }
        \n
        """
    }
    
    func CommonGetter(_ className: String, _ ivarName: String) -> String {
        return """
        - (\(className) *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[\(className) alloc] init];
            }
            return _\(ivarName);
        }
        \n
        """
    }
    
}
