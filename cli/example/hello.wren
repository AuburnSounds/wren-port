if (System.isDebugBuild) {
    System.print("Host compiler with -debug")
    System.print(4.fromString("42.87") + 1)
} else {
    System.print("Host compiler without -debug")
}
