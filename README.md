# Grafana-to-ntfy
This service is a utility webhook server for the grafana alert webhooks, which sends a notification to your ntfy url ([ntfy.sh](https://ntfy.sh/)), and consequtively to your phone/desktop.  

### Usage
First, clone the repository or open and copy `.env.sample` file. To configure it, enter your ntfy.sh's (or your own instance's) url and basic authorization credentials for requests from grafana. Here is an example:  
```bash
NTFY_URL=https://ntfy.sh/test_b694d03045a7502f
BAUTH_USER=admin
BAUTH_PASS=test
```
**Note:** ntfy.sh urls are publicly available, so better add some random string in the end to make it safe (or make the url path completely random).  
  
Then you would need to spin up the container, you can use existing Dockefile and docker-compose.yml or create your own. Just make sure that container is on the same network as grafana instance, so grafana will be able to send requests.  
  
When the service is running, you can subscribe to configured ntfy.sh topic (in this example it's `test_b694d03045a7502f`) in your phone ntfy app to test it.  
![phone_screenshot_1](./assets/subscribe.jpg)

Now, all that's left is to open grafana and test the notifications. Enter webhook url and path as follows, and don't forget to add basic auth credentials, and finally, press `Test`:
![grafana_screenshot_1](./assets/grafana.png)
  
You should instantly receive a notification:
![phone_screenshot_2](./assets/notification1.jpg)
![phone_screenshot_3](./assets/notification2.jpg)
