import os
import logging
import requests
import pandas as pd
from collections import defaultdict

class Kma_api_collector:
    """
        Request kma apihub to get STN metadata
    """

    def __init__(self):
        """
            Initialize api collector
        """

        # set API Key
        self.key = os.getenv("KMA_KEY")
        if not self.key:
            raise EnvironmentError("KMA_KEY is not set in environment variables")
        
        # Default timeout 
        self.base_timeout = 30

    
    def request_stn_metadata(self):
        """
            Request meta data of stn information
        """
        stn_url = 'https://apihub.kma.go.kr/api/typ01/url/stn_inf.php'
        stn_params = {
            'help' : 0,
            'authKey' : self.key
        }

        # The data will be collected by each columns then converted to pd.dataFrame
        stn_meta_can = defaultdict(list)

        # Request API
        try:
            response = requests.get(stn_url, params=stn_params, 
                                    timeout=self.base_timeout)
            
            # Check api status
            response.raise_for_status()
            
            logging.info('Success to request API')

            # Append each rows into meta can by column
            for data in response.text.splitlines():
                # Check not metadata
                if not data.startswith('#'):
                    splited = data.split()
                    stn_meta_can['STN_ID'].append(int(splited[0]))
                    stn_meta_can['경도'].append(float(splited[1]))
                    stn_meta_can['위도'].append(float(splited[2]))
                    stn_meta_can['STN_SP'].append(int(splited[3]))
                    stn_meta_can['지역'].append(splited[10])

            if not stn_meta_can:
                raise ValueError("KMA API returned empty station metadata")

            # Convert to Pandas data frame
            df = pd.DataFrame(stn_meta_can)
            return df

        except requests.Timeout:
            logging.error('KMA API request timeout')
            raise

        except requests.HTTPError as exc:
            logging.error(f"KMA API HTTP error: {exc}")
            raise

        except Exception:
            logging.exception("Unexpected error caught while requesting KMA API")
            raise



    def request_live_weather(self):
        """
            Request hourly weather condition for all stn provided
        """
        stn_url = 'https://apihub.kma.go.kr/api/typ01/url/kma_sfctm2.php'
        stn_params = {
            'help' : 0,
            'authKey' : self.key
        }

        try:
            response = requests.get(stn_url, params=stn_params, 
                                    timeout=self.base_timeout)
            # Check api status
            response.raise_for_status()

            # Return result
            response.encoding = "utf-8"
            return response.text
        
        except requests.Timeout:
            logging.error(f'KMA API request timeout - {self.ymd+self.hm}')
            raise

        except requests.HTTPError as exc:
            logging.error(f"KMA API HTTP error ({self.ymd+self.hm}): {exc}")
            raise

        except Exception:
            logging.exception(f"Unexpected error caught while requesting KMA API ({self.ymd+self.hm})")
            raise