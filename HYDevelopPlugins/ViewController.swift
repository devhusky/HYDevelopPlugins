//
//  ViewController.swift
//  HYDevelopPlugins
//
//  Created by 莫名 on 2020/10/12.
//

import Cocoa

class ViewController: NSViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    func test() {
        let propertyLine = "@property (nonatomic, strong) NSMutableArray *selectedFields;"
        let pattern = ".*(<.*>).\\*(.*);"
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let matches = regex.matches(in: propertyLine, options: [], range: NSRange(location: 0, length: propertyLine.count))

        for match in matches {
            for idx in 0..<match.numberOfRanges {
                if let range = Range(match.range(at: idx), in: propertyLine) {
                    print(range)
                    print(String(propertyLine[range]))
                }
            }
        }
    }

}

