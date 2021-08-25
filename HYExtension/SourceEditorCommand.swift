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
        var headerName = (currentLine as NSString).substring(with: range)
        
        do {
            //规则校验
            let pattern = "^[<|a-z|A-Z|_][\\w|+|/|\\.]*[>|a-z|A-Z|\\d]$"
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let matchs = regex.matches(in: headerName, options: .reportProgress, range: NSRange(location: 0, length: headerName.count))
            if matchs.count == 0 {
                return
            }
            
            if !headerName.contains(".h") {
                headerName += ".h"
            }
            //查找插入位置
            var insertTargetLine = NSNotFound
            for (i, line) in lines.enumerated() {
                if line.contains("#import") {
                    if line.contains(headerName) {
                        return
                    }
                    insertTargetLine = i + 1
                }
                if line.contains("@interface") || line.contains("@implementation") {
                    break
                }
            }
            
            if insertTargetLine != NSNotFound {
                if headerName.hasPrefix("<") && headerName.hasSuffix(">") {
                    invocation.buffer.lines.insert("#import \(headerName)", at: insertTargetLine)
                } else {
                    invocation.buffer.lines.insert("#import \"\(headerName)\"", at: insertTargetLine)
                }
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
        
        //获取类名
        var findClassName = ""
        for i in (0..<startLine).reversed() {
            let line = lines[i].replacingOccurrences(of: " ", with: "")
            if !line.contains("@interface") {
                continue
            }
            
            var suffixRange = (line as NSString).range(of: "(")
            if suffixRange.location == NSNotFound {
                suffixRange = (line as NSString).range(of: ":")
            }
            if suffixRange.location == NSNotFound {
                return
            }
            
            let startLocation = "@interface".count
            let subRange = NSRange(location: startLocation, length: suffixRange.location - startLocation)
            findClassName = (line as NSString).substring(with: subRange)
            break
        }
        if findClassName.count == 0 {
            return
        }
        
        //获取插入位置
        var insertTargetLine = 0
        var didFindClassImpl = false
        var needBlackLine = false
        for (i, line) in lines.enumerated() {
            let line = line.replacingOccurrences(of: " ", with: "")
            print(line)
            if line.hasPrefix("@implementation\(findClassName)") {
                didFindClassImpl = true;
                continue
            }
            if !didFindClassImpl {
                continue
            }
            
            if line.hasPrefix("@end") {
                for j in (0..<i).reversed() {
                    let targetLine = lines[j].trimmingCharacters(in: .whitespacesAndNewlines)
                    if targetLine.count > 0 {
                        insertTargetLine = j + 1
                        needBlackLine = (j == i - 1)
                        break
                    }
                }
                break
            }
        }
        if insertTargetLine > 0 && insertTargetLine <= lines.count {
            let targetGetters = "\n" + insertPropertyGetters.joined(separator: "\n\n") + (needBlackLine ? "\n\n" : "\n")
            buffer.lines.insert(targetGetters, at: insertTargetLine)
        }
    }
    
}

extension SourceEditorCommand {
    
    func getPropertyClassNameAndIvarName(_ line: String) -> (String, String)? {
        if !line.contains("@property") {
            return nil
        }
        var propertyLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixRange = (propertyLine as NSString).range(of: ")")
        let suffixRange = (propertyLine as NSString).range(of: ";")
        
        if suffixRange.location == NSNotFound {
            return nil
        }
        
        let subFromIndex = prefixRange.location == NSNotFound ? "@property".count : prefixRange.location + 1
        let subRange = NSRange(location: subFromIndex, length: suffixRange.location - subFromIndex)
        propertyLine = (propertyLine as NSString).substring(with: subRange)
        propertyLine = propertyLine.replacingOccurrences(of: "\n", with: "")
        propertyLine = propertyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !propertyLine.contains("*") {
            return nil
        }
        
        let results = propertyLine.components(separatedBy: "*")
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
        case "UITableView":
            return UITableViewGetter(ivarName)
        case "UIImageView":
            return UIImageViewGetter(ivarName)
        case "UILabel":
            return UILabelGetter(ivarName)
        case "UIButton":
            return UIButtonGetter(ivarName)
        case "UICollectionView":
            return UICollectionViewGetter(ivarName)
        default:
            return CommonGetter(className, ivarName)
        }
    }
    
    func UITableViewGetter(_ ivarName: String) -> String {
        return """
        - (UITableView *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[UITableView alloc] initWithFrame:self.view.bounds];
                _\(ivarName).dataSource = self;
                _\(ivarName).delegate = self;
            }
            return _tableView;
        }
        """
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
        """
    }
    
    func UICollectionViewGetter(_ ivarName: String) -> String {
        return """
        - (UICollectionView *)\(ivarName) {
            if (!_\(ivarName)) {
                UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
                _\(ivarName) = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
                _\(ivarName).dataSource = self;
                _\(ivarName).delegate = self;
            }
            return _\(ivarName);
        }
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
        """
    }
    
}
