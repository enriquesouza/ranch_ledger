'use strict';

const fs = require('fs');
const path = require('path');
const { ethers } = require('ethers');

const RPC_URL = process.env.RPC_URL || 'http://127.0.0.1:8545';
const DEPLOY_FILE =
  process.env.DEPLOY_FILE || path.join(__dirname, '..', 'deployments', 'local.json');

// Lazy-load the canonical ABI from the Foundry build artifact so the tuple
// signatures for getBovine / getVaccines etc. always match the source.
let _abiCache;
function getAbi() {
  if (_abiCache) return _abiCache;
  const artifact = path.join(__dirname, '..', 'out', 'BovineTracking.sol', 'BovineTracking.json');
  if (!fs.existsSync(artifact)) {
    throw new Error(
      `ABI artifact missing: ${artifact}\nRun 'npm run build' (forge build) first.`
    );
  }
  const { abi } = JSON.parse(fs.readFileSync(artifact, 'utf8'));
  _abiCache = abi;
  return abi;
}

let _deployCache;
function readDeployment() {
  if (_deployCache) return _deployCache;
  const raw = fs.readFileSync(DEPLOY_FILE, 'utf8');
  _deployCache = JSON.parse(raw);
  return _deployCache;
}

function getProvider() {
  return new ethers.JsonRpcProvider(RPC_URL);
}

function getContract() {
  const provider = getProvider();
  const { BovineTracking: address } = readDeployment();
  if (!address) {
    throw new Error(
      `BovineTracking address missing in ${DEPLOY_FILE} - run 'npm run deploy' first`
    );
  }
  return new ethers.Contract(address, getAbi(), provider);
}

function getContractWithSigner(signer) {
  return getContract().connect(signer);
}

function getDefaultSigner() {
  const provider = getProvider();
  const pk = process.env.PRIVATE_KEY;
  if (!pk) throw new Error('PRIVATE_KEY env var required for write operations');
  return new ethers.Wallet(pk, provider);
}

async function _send(fn) {
  const tx = await fn();
  const rcpt = await tx.wait();
  return rcpt;
}

async function addBovine(bovineData) {
  const signer = getDefaultSigner();
  const contract = getContractWithSigner(signer);
  const tx = await contract.addBovine(
    bovineData.name,
    bovineData.age,
    bovineData.breed,
    bovineData.location,
    bovineData.owner ?? signer.address
  );
  const rcpt = await tx.wait();
  const log = rcpt.logs.find((l) => l.address.toLowerCase() === contract.target.toLowerCase());
  if (!log) throw new Error('BovineAdded event not found in receipt');
  const parsed = contract.interface.parseLog(log);
  return Number(parsed.args.id);
}

async function addVaccine(bovineId, name, date) {
  const contract = getContractWithSigner(getDefaultSigner());
  return _send(() => contract.addVaccine(bovineId, name, date));
}

async function addMovement(bovineId, fromLocation, toLocation, date) {
  const contract = getContractWithSigner(getDefaultSigner());
  return _send(() => contract.addMovement(bovineId, fromLocation, toLocation, date));
}

async function addFeed(bovineId, foodType, origin, quantity, date) {
  const contract = getContractWithSigner(getDefaultSigner());
  return _send(() => contract.addFeed(bovineId, foodType, origin, quantity, date));
}

async function addHealthExam(bovineId, examType, result, date) {
  const contract = getContractWithSigner(getDefaultSigner());
  return _send(() => contract.addHealthExam(bovineId, examType, result, date));
}

async function addAbattoirProcess(bovineId, abattoir, abattoirDate, processing, date) {
  const contract = getContractWithSigner(getDefaultSigner());
  return _send(() =>
    contract.addAbattoirProcess(bovineId, abattoir, abattoirDate, processing, date)
  );
}

function _toObj(raw) {
  return {
    id: Number(raw.id),
    name: raw.name,
    age: Number(raw.age),
    breed: raw.breed,
    location: raw.location,
    owner: raw.owner,
    vaccines: (raw.vaccines || []).map((v) => ({ name: v.name, date: Number(v.date) })),
    movements: (raw.movements || []).map((m) => ({
      fromLocation: m.fromLocation,
      toLocation: m.toLocation,
      date: Number(m.date),
    })),
    feeds: (raw.feeds || []).map((f) => ({
      foodType: f.foodType,
      origin: f.origin,
      quantity: Number(f.quantity),
      date: Number(f.date),
    })),
    healthExams: (raw.healthExams || []).map((h) => ({
      examType: h.examType,
      result: h.result,
      date: Number(h.date),
    })),
    abattoirProcesses: (raw.abattoirProcesses || []).map((a) => ({
      abattoir: a.abattoir,
      abattoirDate: Number(a.abattoirDate),
      processing: a.processing,
      date: Number(a.date),
    })),
  };
}

async function getBovine(id) {
  const contract = getContract();
  return _toObj(await contract.getBovine(id));
}

module.exports = {
  addBovine,
  addVaccine,
  addMovement,
  addFeed,
  addHealthExam,
  addAbattoirProcess,
  getBovine,
  getContract,
  getAbi,
  readDeployment,
};
