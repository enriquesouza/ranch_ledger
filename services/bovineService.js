const Web3 = require('web3');
const contractABI = require('./BovineTracking.json');

const provider = new Web3.providers.HttpProvider('http://localhost:8545'); // Update with your Ethereum provider URL
const web3 = new Web3(provider);
const contractAddress = '0x123456789...'; // Update with your contract address
const contract = new web3.eth.Contract(contractABI, contractAddress);

async function addBovine(bovineData) {
  try {
    const accounts = await web3.eth.getAccounts();
    const transaction = contract.methods.addBovine(
      bovineData.name,
      bovineData.age,
      bovineData.breed,
      bovineData.location
    );
    const gas = await transaction.estimateGas();
    const result = await transaction.send({
      from: accounts[0],
      gas,
    });
    return result.events.BovineAdded.returnValues.bovineId;
  } catch (error) {
    console.error('Error adding bovine:', error);
    throw error;
  }
}

async function addVaccine(bovineId, name, date) {
  try {
    const accounts = await web3.eth.getAccounts();
    const transaction = contract.methods.addVaccine(bovineId, name, date);
    const gas = await transaction.estimateGas();
    await transaction.send({
      from: accounts[0],
      gas,
    });
  } catch (error) {
    console.error('Error adding vaccine:', error);
    throw error;
  }
}

async function addMovement(bovineId, fromLocation, toLocation, date) {
  try {
    const accounts = await web3.eth.getAccounts();
    const transaction = contract.methods.addMovement(bovineId, fromLocation, toLocation, date);
    const gas = await transaction.estimateGas();
    await transaction.send({
      from: accounts[0],
      gas,
    });
  } catch (error) {
    console.error('Error adding movement:', error);
    throw error;
  }
}

async function addFeed(bovineId, foodType, origin, quantity, date) {
  try {
    const accounts = await web3.eth.getAccounts();
    const transaction = contract.methods.addFeed(bovineId, foodType, origin, quantity, date);
    const gas = await transaction.estimateGas();
    await transaction.send({
      from: accounts[0],
      gas,
    });
  } catch (error) {
    console.error('Error adding feed:', error);
    throw error;
  }
}

async function addHealthExam(bovineId, examType, result, date) {
  try {
    const accounts = await web3.eth.getAccounts();
    const transaction = contract.methods.addHealthExam(bovineId, examType, result, date);
    const gas = await transaction.estimateGas();
    await transaction.send({
      from: accounts[0],
      gas,
    });
  } catch (error) {
    console.error('Error adding health exam:', error);
    throw error;
  }
}

async function addAbattoirProcess(bovineId, abattoir, abattoirDate, processing, date) {
  try {
    const accounts = await web3.eth.getAccounts();
    const transaction = contract.methods.addAbattoirProcess(bovineId, abattoir, abattoirDate, processing, date);
    const gas = await transaction.estimateGas();
    await transaction.send({
      from: accounts[0],
      gas,
    });
  } catch (error) {
    console.error('Error adding abattoir process:', error);
    throw error;
  }
}

module.exports = {
  addBovine,
  addVaccine,
  addMovement,
  addFeed,
  addHealthExam,
  addAbattoirProcess,
};
