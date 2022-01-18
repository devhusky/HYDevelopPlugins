//
//  GeneratePropertyGetter.swift
//  HYExtension
//
//  Created by 莫名 on 2021/8/25.
//

import Foundation
import XcodeKit

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
                //获取属性协议
                let protocolName = getPropertyProtocolName(line)
                //替换属性行里边的协议 防止获取属性名以*作为截断不准确问题
                let notProtocolLine = line.replacingOccurrences(of: protocolName, with: "")
                //解析属性的类名、成员变量名
                if let result = getPropertyClassNameAndIvarName(notProtocolLine) {
                    if let getter = generateGetter(with: result.0, ivarName: result.1, protocolName: protocolName) {
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
        if results.count < 2 {
            return nil
        }
        let className = results.first!.replacingOccurrences(of: " ", with: "")
        let ivarName = results.last!.replacingOccurrences(of: " ", with: "")
        return (className, ivarName)
    }
    
    func getPropertyProtocolName(_ line: String) -> String {
        let pattern = ".*(<.*>).*;"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ""
        }
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: line.count))
        for match in matches {
            if let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return ""
    }
    
}

extension SourceEditorCommand {
    
    func generateGetter(with className: String, ivarName: String, protocolName: String) -> String? {
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
            return CommonGetter(className, ivarName, protocolName)
        }
    }
    
    func UITableViewGetter(_ ivarName: String) -> String {
        return """
        - (UITableView *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[UITableView alloc] initWithFrame:self.view.bounds];
                _\(ivarName).dataSource = self;
                _\(ivarName).delegate = self;
                [_\(ivarName) registerClass:[UITableViewCell class] forCellReuseIdentifier:NSStringFromClass(UITableViewCell.class)];
                if (@available(iOS 11.0, *)) {
                    _\(ivarName).contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
                }
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
                _\(ivarName).contentMode = UIViewContentModeScaleAspectFit;
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
                _\(ivarName).backgroundColor = [UIColor whiteColor];
            }
            return _\(ivarName);
        }
        """
    }
    
    func CommonGetter(_ className: String, _ ivarName: String, _ protocolName: String) -> String {
        return """
        - (\(className)\(protocolName) *)\(ivarName) {
            if (!_\(ivarName)) {
                _\(ivarName) = [[\(className)\(protocolName) alloc] init];
            }
            return _\(ivarName);
        }
        """
    }
    
}
