import express from 'express';

import MessageResponse from '../interfaces/MessageResponse';
import configurations from './configurations';

const router = express.Router();

router.get<{}, MessageResponse>('/', (req, res) => {
  res.json({
    message: 'API - 👋🌎🌍🌏',
  });
});

router.use('/configurations', configurations);

export default router;
