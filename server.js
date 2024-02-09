const express = require('express');
const mongoose = require('mongoose');
const Bovine = require('./models/bovine');

mongoose.connect('mongodb://localhost/bovine-tracker', { useNewUrlParser: true, useUnifiedTopology: true })
  .then(() => {
    console.log('Connected to MongoDB');
  })
  .catch((err) => {
    console.error('Error connecting to MongoDB:', err);
  });

const app = express();
app.use(express.json());

app.post('/bovines', async (req, res) => {
  const bovineData = req.body;

  try {
    // Step 1: Persist in MongoDB
    const bovine = new Bovine(bovineData);
    await bovine.save();

    // Step 2: Call method to persist on the blockchain
    await persistOnBlockchain(bovineData);

    res.status(201).json({ success: true, message: 'Bovine created successfully' });
  } catch (error) {
    console.error('Error creating bovine:', error);
    res.status(500).json({ success: false, message: 'Failed to create bovine' });
  }
});

async function persistOnBlockchain(bovineData) {
  try {
    // Method to persist the bovine on the blockchain
    // Replace with your own implementation
    // Example of calling the BovineTracking smart contract:
    // await bovineTrackingContract.methods.addBovine(...).send({ from: ... });
    console.log(`Persisting bovine on the blockchain: ${bovineData.name}`);
  } catch (error) {
    console.error('Error persisting bovine on the blockchain:', error);
    throw error; // Rollback changes if blockchain persistence fails
  }
}

const PORT = 3000;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
