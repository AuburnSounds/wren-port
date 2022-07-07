
class Test {
    construct new(id) {

    }

    foreign myfun_(a, b, c)
}

class Test2 {
    construct new(id) {
        _e = Test.new(id)
    }

    myprop=(x) {
        _e.myfun_(0, 1, x)
    }
}

var b = Test2.new("lol")
b.myprop = 0.65