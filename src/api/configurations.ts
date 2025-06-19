import { execFile } from 'child_process';
import express from 'express';

const router = express.Router();

const clients = {
  'demo-api-key': {
    config_version: 1.0,
    containers: [
      {
        container: "awg",
        awg: {
          client_priv_key: "yJ7/mG3fajAevZ6ozTbYmbonwQ2nfjqsh8FBVw0Ew3w=",
          client_ip: "10.0.0.238",
          server_pub_key: "18HGq+NGYrA+NBtkUrK2bAjoU0w/amKROGsdxUkzilw=",
          server_ip: "164.90.142.218",
          server_port: "36016",
          junkPacketCount: "0",
          junkPacketMinSize: "0",
          junkPacketMaxSize: "0",
          initPacketJunkSize: "0",
          responsePacketJunkSize: "0",
          initPacketMagicHeader: "00000000",
          responsePacketMagicHeader: "00000000",
          underloadPacketMagicHeader: "00000000",
          transportPacketMagicHeader: "00000000"
        }
      }
    ],
    defaultContainer: "awg",
    description: "Ruchey VPN",
    name: "Ruchey VPN"
  }
};

router.get('/request/awg/', (req, res) => {
  console.log(`[${new Date().toISOString()}] /request/awg/ called from IP: ${req.ip}`);
  execFile('/bin/bash', ['/scripts/generate_config.sh'], (error, stdout, stderr) => {
    if (error) {
      console.error(`[${new Date().toISOString()}] Ошибка при генерации:`, error);
      if (stderr) {
        console.error(`[${new Date().toISOString()}] STDERR: ${stderr}`);
      }
      return res.status(500).send('Ошибка при генерации конфига');
    }

    console.log(`[${new Date().toISOString()}] Конфиг успешно сгенерирован для IP: ${req.ip}`);
    res.send(stdout);
  });


  // const apiKey: string | undefined = req.query.api_key?.toString();
  // if (!apiKey) {
  //   return res.status(400).json({ error: 'Missing api_key' });
  // }
  // const config = { config: true };
  // if (!config) {
  //   return res.status(403).json({ error: 'Invalid api_key' });
  // }
});

export default router;
