# ranch_ledger
```
+-------------------+
| BovineTracking    |
+-------------------+
| - bovine          |
+-------------------+
| + addBovine()                            |
| + addVaccine()                           |
| + addMovement()                          |
| + addFeed()                              |
| + addHealthExam()                        |
| + setAbattoirProcess()                   |
| + getBovine()                            |
| + getVaccineCount()                      |
| + getVaccine()                           |
| + getMovementCount()                     |
| + getMovement()                          |
| + getFeedCount()                         |
| + getFeed()                              |
| + getHealthExamCount()                   |
| + getHealthExam()                        |
| + getAbattoirProcess()                   |
+-------------------------------------------+

+---------+
| Bovine  |
+---------+
| - name          |
| - age           |
| - breed         |
| - location      |
| - vaccines      |
| - movements     |
| - feeds         |
| - healthExams   |
| - abattoirProcess |
+------------------+

+---------+
| Vaccine |
+---------+
| - name          |
| - date          |
+------------------+

+----------+
| Movement |
+----------+
| - fromLocation |
| - toLocation   |
| - date         |
+-----------------+

+---------+
| Feed    |
+---------+
| - type          |
| - origin        |
| - quantity      |
+------------------+

+--------------+
| HealthExam   |
+--------------+
| - examType     |
| - result       |
| - date         |
+-----------------+

+------------------+
| AbattoirProcess |
+------------------+
| - abattoir      |
| - abattoirDate  |
| - processing    |
+------------------+
```

This diagram represents the relationships and attributes of each class and struct within the contract. The `BovineTracking` class has an association with the `Bovine`, `Vaccine`, `Movement`, `Feed`, `HealthExam`, and `AbattoirProcess` classes/structs, representing the data structure of the contract and the relationships between the entities.


## Test

```
npx truffle create test BovineTracking.sol
npx truffle test 
```