import AppKit
import Foundation
// Deterministic vector drawing; matches Resources/AppIcon.svg.
let destination = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.png"
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let cg = NSGraphicsContext.current!.cgContext
cg.translateBy(x: 0, y: 1024); cg.scaleBy(x: 1, y: -1)
let bg = CGPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832), cornerWidth: 190, cornerHeight: 190, transform: nil)
cg.saveGState(); cg.addPath(bg); cg.clip()
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [NSColor(srgbRed: 19/255, green: 54/255, blue: 82/255, alpha: 1).cgColor, NSColor(srgbRed: 7/255, green: 23/255, blue: 39/255, alpha: 1).cgColor] as CFArray
cg.drawLinearGradient(CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0,1])!, start: CGPoint(x: 96,y: 96), end: CGPoint(x: 928,y: 928), options: [])
cg.restoreGState()
let cyan = NSColor(srgbRed: 77/255, green: 224/255, blue: 223/255, alpha: 1).cgColor
let white = NSColor(srgbRed: 246/255, green: 250/255, blue: 1, alpha: 1).cgColor
cg.setFillColor(cyan)
cg.addPath(CGPath(roundedRect: CGRect(x:224,y:412,width:104,height:200), cornerWidth:26,cornerHeight:26,transform:nil));cg.fillPath()
cg.setFillColor(NSColor(srgbRed:19/255,green:54/255,blue:82/255,alpha:1).cgColor);cg.fillEllipse(in:CGRect(x:266,y:560,width:20,height:20))
func stroke(_ points:[CGPoint], color:CGColor, width:CGFloat) {
 cg.setStrokeColor(color);cg.setLineWidth(width);cg.setLineCap(.round);cg.setLineJoin(.round);cg.beginPath();cg.addLines(between:points);cg.strokePath()
}
stroke([CGPoint(x:370,y:512),CGPoint(x:402,y:512),CGPoint(x:432,y:444),CGPoint(x:480,y:588),CGPoint(x:528,y:436),CGPoint(x:566,y:512),CGPoint(x:602,y:512)], color:cyan,width:36)
cg.setFillColor(white);cg.setStrokeColor(white);cg.setLineWidth(12);cg.setLineJoin(.round)
cg.beginPath();cg.addLines(between:[CGPoint(x:640,y:464),CGPoint(x:674,y:464),CGPoint(x:738,y:408),CGPoint(x:738,y:616),CGPoint(x:674,y:560),CGPoint(x:640,y:560)]);cg.closePath();cg.drawPath(using:.fillStroke)
cg.setStrokeColor(white);cg.setLineWidth(26);cg.setLineCap(.round);cg.beginPath();cg.move(to:CGPoint(x:786,y:450));cg.addQuadCurve(to:CGPoint(x:786,y:574),control:CGPoint(x:840,y:512));cg.strokePath()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination))
