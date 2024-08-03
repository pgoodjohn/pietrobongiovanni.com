---
title: "Build a HTTP API Checker with Golang"
date: 2024-08-03T07:14:06+02:00
slug: "go-http-api-chekcer"
description: ""
keywords: ["golang", "programming", "ci"]
draft: false
tags: ["golang"]
math: false
toc: false
---

We recently deployed a new API Gateway for the [Mollie Public API](https://docs.mollie.com/reference/overview). This is now responsible for authenticating every HTTP request that `https://api.mollie.com` receives before forwarding it to the correct upstream service based on the URL.

This is clearly a very critical piece of infrastructure that needs to be as reliable as possible. As part of our strategy to ensure we don't have to worry about it too much, we wanted to integrate a step in our CI process that would automatically perform some HTTP requests to the system after every new roll-out. Our first idea was to build a simple shell script that would use cURL to perform some requests, but I quickly came to the realisation that with a similar amount of time and effort, I could've built something much better and easier to maintain using a more "modern" programming language.

I decided to use Golang for this small project because I knew it wouldn't be a massive amount of code (in the end the whole set up came down to around ~200 lines of Go code), and because it is the preferred language of our Infra people. The main constraint I had was to be limited only to Go's standard library: no external dependencies.

## Gathering Requirements

I wanted a tool that could easily be used for different environment and to which tests could be easily added. My initial idea was to have a simple command that could be ran like this:

```bash
$ api-tests --tests=file.json
```

Where `file.json` would contain the definition and some variables for all the tests, something like:

```json
{
    "testName": "Test Name",
    "url": "https://the-url-to.call/
    "expectedStatusCode": 200
}
```

This way, with a few files (`staging.json`, `production.json`) it would be easy to add new tests to a single test-suite or even add more test suites to be ran in different environment.

## Implementation

One of my main goals with this project was to make it easier to extend the actual testing function, allowing users to add extra assertions or including whole new functionalities, so this was the first method I implemented. 

It now looks something like this:

```go
func (t TestRunner) testEndpoint(test EndpointTest) EndpointTestResult {

	req, err := http.NewRequest("GET", test.URL, nil)
	if err != nil {
		log.Fatal(err)
	}

	if t.DebugMode {
		test.PrintDebugInfo()
	}

	// Create an HTTP client
	client := &http.Client{}

	// Send the request and record response time
	startTime := time.Now()
	res, err := client.Do(req)
	responseTime := time.Since(startTime)
	if err != nil {
		log.Fatal(err)
	}
	defer res.Body.Close()

	if res.StatusCode != test.ExpectedStatusCode {
		return EndpointTestResult{
			TestName:     test.TestName,
			Success:      false,
			ErrorMessage: fmt.Sprintf("Expected status code %d, got %d", test.ExpectedStatusCode, res.StatusCode),
			ResponseTime: responseTime,
		}
	}

	if res.Header.Get("x-mollie-api-gateway-requestid") == "" {
		return EndpointTestResult{
			TestName:     test.TestName,
			Success:      false,
			ErrorMessage: "Request ID Header was not present in response",
			ResponseTime: responseTime,
		}
	}

	return EndpointTestResult{
		TestName:     test.TestName,
		Success:      true,
		ErrorMessage: "",
		ResponseTime: responseTime,
	}
}
```

This method takes an instance of `EndpointTest` as a parameter, which is just a struct definition for the data supplied in the input JSON file:

```go
type EndpointTest struct {
	TestName           string
	URL                string
	ExpectedStatusCode int
}
```

And performs the HTTP request according to the specification, returning a `EndpointTestResult` object on completion, which is then used by the rest of the program to print results after execution.

To easily evolve the configuration across all tests, and making shared properties accessible, I introduced a new `TestRunner` type (you can see it already in the `testEndpoint` method definition):

```go
type TestRunner struct {
	DebugMode bool
	StartTime  time.Time
	TestFilePath string
	SuccessFullTest bool
	EndpointTests []EndpointTest
	TestResults []EndpointTestResult
}
```

This struct contains the input details that are passed as command line arguments, as well as the list of tests and the final result of the test run. Using golang's standard library meant I only had access to the `flag` package to declare and validate incoming CLI parameters, so I ended up with an intialiser function that looks something like the following:

```go
func InitTestRunner(startTime time.Time) TestRunner {

	// Set up inputs
	var testFilePath = flag.String("tests", "", "Test file path")
	var debug = flag.Bool("debug", false, "Debug mode")
	flag.Parse()
	// ---

	// Validate inputs
	if *testFilePath == "" {
		fmt.Println("Test file path is required")
		printHelpMessage()
		os.Exit(1)
	}
	// ---

	// Load tests file content
	file, err := ioutil.ReadFile(*testFilePath)
	if err != nil {
		log.Fatal(err)
	}
	var file_contents struct {
		Tests []EndpointTest `json:"tests"`
	}
	if err := json.Unmarshal(file, &file_contents); err != nil {
		log.Fatal(err)
	}
	// ---

	return TestRunner{
		DebugMode: *debug,
		StartTime: startTime,
		TestFilePath: *testFilePath,
		SuccessFullTest: true,
		EndpointTests: file_contents.Tests,
	}	
}
```

In this way, with a simple call like:

```golang
var testRunner := InitTestRunner(time.Now())
```

the test runner is ready to go.

In the end, my `main()` function ended up looking like the following:

```go
func main() {
	InitTestRunner(time.Now()).RunTests()
}
```

## Execution

With an example `tests.json` file such as:

```json
{
    "tests": [
        {
            "testName": "Expected 401",
            "url": "http://localhost:9080",
            "expectedStatusCode": 401,
            "useBearerToken": false
        },
        {
            "testName": "Expect 200",
            "url": "http://localhost:9080",
            "expectedStatusCode": 200,
            "useBearerToken": true
        }
    ]
}
```

Running the API tester will result in the following output:

```bash
? go run main.go  --tests=tests.json             
| --------------------------------------------- |
| 💡 | TestCase                                 | Total Duration: 00.53s 
| ------------- ------------------------------- |
| ✅ | Expected 401                             | API Response Time: 00.47s |   
| ❌ | Expect 200                               | API Response Time: 00.06s | Expected status code 200, got 401  

🚨 Some tests failed

exit status 1
```

🥳