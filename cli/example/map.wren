var capitals = {}
capitals["Georgia"] = "Atlanta"
capitals["Idaho"] = "Boise"
capitals["Maine"] = "Augusta"
System.print(capitals.containsKey("Maine")) // "true"
System.print(capitals.remove("Georgia"))    // "Atlanta"
System.print(capitals)                      // "{Maine: Augusta, Idaho: Boise}"
capitals.clear()
System.print(capitals.count)                // "0"
capitals = {"Georgia": null}
System.print(capitals["Georgia"])           // "null" (though key exists)
System.print(capitals["Idaho"])             // "null" 
System.print(capitals.containsKey("Georgia")) // "true"
System.print(capitals.containsKey("Idaho"))   // "false"