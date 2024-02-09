const mongoose = require('mongoose');

const vaccineSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
  },
  date: {
    type: Number,
    required: true,
  },
});

const movementSchema = new mongoose.Schema({
  fromLocation: {
    type: String,
    required: true,
  },
  toLocation: {
    type: String,
    required: true,
  },
  date: {
    type: Number,
    required: true,
  },
});

const feedSchema = new mongoose.Schema({
  foodType: {
    type: String,
    required: true,
  },
  origin: {
    type: String,
    required: true,
  },
  quantity: {
    type: Number,
    required: true,
  },
  date: {
    type: Number,
    required: true,
  },
});

const healthExamSchema = new mongoose.Schema({
  examType: {
    type: String,
    required: true,
  },
  result: {
    type: String,
    required: true,
  },
  date: {
    type: Number,
    required: true,
  },
});

const abattoirProcessSchema = new mongoose.Schema({
  abattoir: {
    type: String,
    required: true,
  },
  abattoirDate: {
    type: Number,
    required: true,
  },
  processing: {
    type: String,
    required: true,
  },
  date: {
    type: Number,
    required: true,
  },
});

const bovineSchema = new mongoose.Schema({
  id: {
    type: Number,
    required: true,
  },
  name: {
    type: String,
    required: true,
  },
  age: {
    type: Number,
    required: true,
  },
  breed: {
    type: String,
    required: true,
  },
  location: {
    type: String,
    required: true,
  },
  vaccines: {
    type: [vaccineSchema],
    default: [],
  },
  movements: {
    type: [movementSchema],
    default: [],
  },
  feeds: {
    type: [feedSchema],
    default: [],
  },
  healthExams: {
    type: [healthExamSchema],
    default: [],
  },
  abattoirProcesses: {
    type: [abattoirProcessSchema],
    default: [],
  },
});

const Bovine = mongoose.model('Bovine', bovineSchema);

module.exports = Bovine;
