import { exec, execFile } from 'child_process';
import express from 'express';

const router = express.Router();

// router.get('/request/awg/', (req, res) => {
//   console.log(`[${new Date().toISOString()}] /request/awg/ called from IP: ${req.ip}`);

//   execFile('/bin/sh', ['/scripts/generate_config.sh'], (error, stdout, stderr) => {
//     if (error) {
//       console.error(`[${new Date().toISOString()}] Ошибка при генерации:`, error);
//       if (stderr) {
//         console.error(`[${new Date().toISOString()}] STDERR: ${stderr}`);
//       }
//       return res.status(500).send('Ошибка при генерации конфига');
//     }

//     console.log(`[${new Date().toISOString()}] Конфиг успешно сгенерирован для IP: ${req.ip}`);
//     console.log(stdout);
//     res.send({ config: stdout });
//   });


//   // const apiKey: string | undefined = req.query.api_key?.toString();
//   // if (!apiKey) {
//   //   return res.status(400).json({ error: 'Missing api_key' });
//   // }
//   // const config = { config: true };
//   // if (!config) {
//   //   return res.status(403).json({ error: 'Invalid api_key' });
//   // }
// });

router.get('/key/:id', (req, res) => {
  const { id } = req.params;
  if (!id) {
    return res.status(400).json({ error: 'Missing id parameter' });
  }

  execFile('/bin/sh', ['/newclient.sh', id, 'gateway.getruchey.ru', '/etc/wireguard/wg0.conf', 'wg'], (error, stdout, stderr) => {
    if (error) {
      console.error(`[${new Date().toISOString()}] Ошибка при генерации:`, error);
      if (stderr) {
        console.error(`[${new Date().toISOString()}] STDERR: ${stderr}`);
      }
      return res.status(500).send('Ошибка при генерации ключа');
    }

    console.log(`[${new Date().toISOString()}] Конфиг успешно сгенерирован для ID: ${id}`);
    console.log(stdout);

    const containerName = 'my_python_container';
    const pythonScript = `python3 awg-decode.py --encode users/${id}/${id}.conf`; // Путь внутри контейнера
    const command = `docker exec ${containerName} ${pythonScript}`;

    exec(command, (error, stdout, stderr) => {
        if (error) {
          console.error(`Ошибка: ${error.message}`);
          return;
        }
        if (stderr) {
          console.error(`stderr: ${stderr}`);
          return;
        }

        res.send({ key: stdout });
    });
  });


  // console.log(`[${new Date().toISOString()}] /request/key/${id} called from IP: ${req.ip}`);
  // execFile('/bin/sh', ['/scripts/generate_key.sh', id], (error, stdout, stderr) => {
  //   if (error) {
  //     console.error(`[${new Date().toISOString()}] Ошибка при генерации ключа:`, error);
  //     if (stderr) {
  //       console.error(`[${new Date().toISOString()}] STDERR: ${stderr}`);
  //     }
  //     return res.status(500).send('Ошибка при генерации ключа');
  //   }
  //   console.log(`[${new Date().toISOString()}] Ключ успешно сгенерирован для id: ${id}, IP: ${req.ip}`);
  //   res.send(stdout);
  // });
});

export default router;
