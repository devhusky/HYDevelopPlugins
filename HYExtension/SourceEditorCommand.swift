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
