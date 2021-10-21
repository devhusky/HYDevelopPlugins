//
//  ImportHeader.swift
//  HYExtension
//
//  Created by 莫名 on 2021/8/25.
//

import Foundation
import XcodeKit

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
