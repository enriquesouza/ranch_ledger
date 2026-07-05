'use strict';

const express = require('express');
const mongoose = require('mongoose');
const Bovine = require('./models/bovine');
const bovineService = require('./services/bovineService');

const MONGODB_URI = process.env.MONGODB_URI || 'mongodb://localhost:27017/bovine-tracker';
const PORT = Number(process.env.PORT || 3000);

async function main() {
  await mongoose.connect(MONGODB_URI);
  console.log('Connected to MongoDB');

  const { BovineTracking: address } = bovineService.readDeployment();
  console.log(`BovineTracking contract: ${address}`);

  const app = express();
  app.use(express.json());

  app.post('/bovines', async (req, res) => {
    const data = req.body;
    try {
      const doc = new Bovine(data);
      await doc.save();

      try {
        const id = await bovineService.addBovine(data);
        doc.chainId = id;
        await doc.save();
        res.status(201).json({ success: true, id, message: 'Bovine created and anchored on-chain' });
      } catch (chainErr) {
        console.error('Blockchain persist failed, rolling back Mongo', chainErr);
        await Bovine.deleteOne({ _id: doc._id });
        res.status(502).json({ success: false, message: 'Blockchain persist failed', error: String(chainErr) });
      }
    } catch (err) {
      console.error('Error creating bovine:', err);
      res.status(500).json({ success: false, message: 'Failed to create bovine' });
    }
  });

  app.post('/bovines/:id/vaccine', async (req, res) => {
    try {
      const { name, date } = req.body;
      await bovineService.addVaccine(req.params.id, name, date);
      res.json({ success: true });
    } catch (err) {
      res.status(500).json({ success: false, error: String(err) });
    }
  });

  app.post('/bovines/:id/movement', async (req, res) => {
    try {
      const { fromLocation, toLocation, date } = req.body;
      await bovineService.addMovement(req.params.id, fromLocation, toLocation, date);
      res.json({ success: true });
    } catch (err) {
      res.status(500).json({ success: false, error: String(err) });
    }
  });

  app.get('/bovines/:id', async (req, res) => {
    try {
      const b = await bovineService.getBovine(req.params.id);
      res.json({ success: true, bovine: b });
    } catch (err) {
      res.status(500).json({ success: false, error: String(err) });
    }
  });

  app.get('/health', (_req, res) => res.json({ ok: true, contract: address }));

  app.listen(PORT, () => console.log(`Server running on http://localhost:${PORT}`));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
