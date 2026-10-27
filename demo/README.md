## Use of Generative AI

We used Claude (Anthropic) during Sprint 1 to help with the following:

- **Test script (test_triggers.sql):** Claude helped write the automated test script that runs valid
  and invalid inserts for each trigger and constraint and reports PASS/FAIL.

How this didn't replace our own learning:

- We came up with the triggers ourselves and tested them by hand in MySQL before using the test script. 
- We then question the output/results for each case and reviewed the generated code to make sure it was returning the correct information.
