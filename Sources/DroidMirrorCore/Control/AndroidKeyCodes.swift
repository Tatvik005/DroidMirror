import Foundation

public enum AndroidKeycode: Int32 {
    case home = 3
    case back = 4
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case camera = 27
    case clear = 28
    case a = 29
    case b = 30
    case c = 31
    case d = 32
    case e = 33
    case f = 34
    case g = 35
    case h = 36
    case i = 37
    case j = 38
    case k = 39
    case l = 40
    case m = 41
    case n = 42
    case o = 43
    case p = 44
    case q = 45
    case r = 46
    case s = 47
    case t = 48
    case u = 49
    case v = 50
    case w = 51
    case x = 52
    case y = 53
    case z = 54
    case comma = 55
    case period = 56
    case tab = 61
    case space = 62
    case enter = 66
    case del = 67 // Backspace
    case grave = 68
    case minus = 69
    case equals = 70
    case leftBracket = 71
    case rightBracket = 72
    case backslash = 73
    case semicolon = 74
    case apostrophe = 75
    case slash = 76
    case menu = 82
    case pageUp = 92
    case pageDown = 93
    case escape = 111
    case forwardDel = 112
    case moveHome = 122
    case moveEnd = 123
    case appSwitch = 187 // Overview / Recents
    case copy = 278
    case paste = 279
    case cut = 277
}

public struct KeyMapper {
    public static func mapMacOSKeyCodeToAndroid(_ keyCode: UInt16) -> AndroidKeycode? {
        switch keyCode {
        case 0: return .a
        case 1: return .s
        case 2: return .d
        case 3: return .f
        case 4: return .h
        case 5: return .g
        case 6: return .z
        case 7: return .x
        case 8: return .c
        case 9: return .v
        case 11: return .b
        case 12: return .q
        case 13: return .w
        case 14: return .e
        case 15: return .r
        case 16: return .y
        case 17: return .t
        case 18: return .num1
        case 19: return .num2
        case 20: return .num3
        case 21: return .num4
        case 22: return .num6
        case 23: return .num5
        case 24: return .equals
        case 25: return .num9
        case 26: return .num7
        case 27: return .minus
        case 28: return .num8
        case 29: return .num0
        case 30: return .rightBracket
        case 31: return .o
        case 32: return .u
        case 33: return .leftBracket
        case 34: return .i
        case 35: return .p
        case 36: return .enter
        case 37: return .l
        case 38: return .j
        case 39: return .apostrophe
        case 40: return .k
        case 41: return .semicolon
        case 42: return .backslash
        case 43: return .comma
        case 44: return .slash
        case 45: return .n
        case 46: return .m
        case 47: return .period
        case 48: return .tab
        case 49: return .space
        case 50: return .grave
        case 51: return .del
        case 53: return .escape
        case 115: return .moveHome
        case 116: return .pageUp
        case 117: return .forwardDel
        case 119: return .moveEnd
        case 121: return .pageDown
        case 123: return .dpadLeft
        case 124: return .dpadRight
        case 125: return .dpadDown
        case 126: return .dpadUp
        default: return nil
        }
    }
}

private extension AndroidKeycode {
    static let num0 = AndroidKeycode(rawValue: 7)!
    static let num1 = AndroidKeycode(rawValue: 8)!
    static let num2 = AndroidKeycode(rawValue: 9)!
    static let num3 = AndroidKeycode(rawValue: 10)!
    static let num4 = AndroidKeycode(rawValue: 11)!
    static let num5 = AndroidKeycode(rawValue: 12)!
    static let num6 = AndroidKeycode(rawValue: 13)!
    static let num7 = AndroidKeycode(rawValue: 14)!
    static let num8 = AndroidKeycode(rawValue: 15)!
    static let num9 = AndroidKeycode(rawValue: 16)!
}
