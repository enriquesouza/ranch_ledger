const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("BovineTracking", function () {
  let bovineTracking;
  let latestBovineId;

  before(async function () {
    const BovineTracking = await ethers.getContractFactory("BovineTracking");
    bovineTracking = await BovineTracking.deploy();
  });

  it("should add a new bovine", async function () {
    const initialBovineCount = await bovineTracking.getTotalBovineCount();

    await bovineTracking.addBovine("Bessie", 5, "Holstein", "Farm A");

    const newBovineCount = await bovineTracking.getTotalBovineCount();

    latestBovineId = Number(newBovineCount);

    expect(newBovineCount).to.equal(Number(initialBovineCount) + 1);
  });

  it("should add a new vaccine", async function () {

    const vaccineName = "COVID-19";
    const vaccineDate = 1632893482; 

    await bovineTracking.addVaccine(latestBovineId, vaccineName, vaccineDate);

    const bovine = await bovineTracking.getBovine(latestBovineId);
    expect(bovine.vaccines[0].name).to.equal(vaccineName);
    expect(bovine.vaccines[0].date).to.equal(vaccineDate);  
  });

  it("should add a new feed", async function () {
    
    const foodType = "Corn";
    const origin = "farm";
    const quantity = 1;
    const date = 1632893482; 

    await bovineTracking.addFeed(latestBovineId, foodType, origin, quantity, date);

    const bovine = await bovineTracking.getBovine(latestBovineId);

    expect(bovine.feeds[0].foodType).to.equal(foodType);
    expect(bovine.feeds[0].origin).to.equal(origin);
    expect(bovine.feeds[0].quantity).to.equal(quantity);
    expect(bovine.feeds[0].date).to.equal(date);
  });

  it("should add multiple movements", async function () {
    
    const movementsToAdd = [
      { fromLocation: "Farm A", toLocation: "Farm B", date: 1632893482 },
      { fromLocation: "Farm B", toLocation: "Farm C", date: 1632893490 },
      { fromLocation: "Farm C", toLocation: "Farm D", date: 1632893498 }
    ];

    for (let i = 0; i < movementsToAdd.length; i++) {
      await bovineTracking.addMovement(latestBovineId, movementsToAdd[i].fromLocation, movementsToAdd[i].toLocation, movementsToAdd[i].date);
    }

    const bovine = await bovineTracking.getBovine(latestBovineId);

    for (let i = 0; i < movementsToAdd.length; i++) {
      expect(bovine.movements[i].fromLocation).to.equal(movementsToAdd[i].fromLocation);
      expect(bovine.movements[i].toLocation).to.equal(movementsToAdd[i].toLocation);
      expect(bovine.movements[i].date).to.equal(movementsToAdd[i].date);
    }
  });

  it("should add multiple abattoir processes", async function () {

    const processesToAdd = [
      { abattoir: "Abattoir A", abattoirDate: 1632893482, processing: "Slaughter", date: 1632893482 },
      { abattoir: "Abattoir B", abattoirDate: 1632893490, processing: "Tanning", date: 1632893490 },
      { abattoir: "Abattoir C", abattoirDate: 1632893498, processing: "Cutting", date: 1632893498 }
    ];

    for (let i = 0; i < processesToAdd.length; i++) {
      await bovineTracking.addAbattoirProcess(latestBovineId, processesToAdd[i].abattoir, processesToAdd[i].abattoirDate, processesToAdd[i].processing, processesToAdd[i].date);
    }

    const bovine = await bovineTracking.getBovine(latestBovineId);

    for (let i = 0; i < processesToAdd.length; i++) {
      expect(bovine.abattoirProcesses[i].abattoir).to.equal(processesToAdd[i].abattoir);
      expect(bovine.abattoirProcesses[i].abattoirDate).to.equal(processesToAdd[i].abattoirDate);
      expect(bovine.abattoirProcesses[i].processing).to.equal(processesToAdd[i].processing);
      expect(bovine.abattoirProcesses[i].date).to.equal(processesToAdd[i].date);
    }
  });

  it("should add multiple health exams", async function () {
    
    const examsToAdd = [
      { examType: "Check-up", result: "Healthy", date: 1632893482 },
      { examType: "X-ray", result: "Normal", date: 1632893490 },
      { examType: "Blood Test", result: "Negative", date: 1632893498 }
    ];

    for (let i = 0; i < examsToAdd.length; i++) {
      await bovineTracking.addHealthExam(latestBovineId, examsToAdd[i].examType, examsToAdd[i].result, examsToAdd[i].date);
    }

    const bovine = await bovineTracking.getBovine(latestBovineId);

    for (let i = 0; i < examsToAdd.length; i++) {
      expect(bovine.healthExams[i].examType).to.equal(examsToAdd[i].examType);
      expect(bovine.healthExams[i].result).to.equal(examsToAdd[i].result);
      expect(bovine.healthExams[i].date).to.equal(examsToAdd[i].date);
    }
  });

  it("should get a bovine", async function () {

    const bovine = await bovineTracking.getBovine(latestBovineId);

    expect(bovine).to.not.be.null;
    expect(bovine.id).to.equal(latestBovineId);
    expect(bovine.name).to.equal("Bessie");
    expect(bovine.age).to.equal(5);
    expect(bovine.breed).to.equal("Holstein");
    expect(bovine.location).to.equal("Farm A");

    expect(bovine.vaccines).to.be.an("array").that.is.not.empty;
    expect(bovine.feeds).to.be.an("array").that.is.not.empty;
    expect(bovine.healthExams).to.be.an("array").that.is.not.empty;
    expect(bovine.movements).to.be.an("array").that.is.not.empty;
    expect(bovine.abattoirProcesses).to.be.an("array").that.is.not.empty;
  });
});