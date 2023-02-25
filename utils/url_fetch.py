import sys
import time

from selenium.common.exceptions import WebDriverException
from selenium.webdriver.remote.webdriver import By
import selenium.webdriver.support.expected_conditions as EC
from selenium.webdriver.support.wait import WebDriverWait

import undetected_chromedriver as uc

input_url = sys.argv[1]
#print(input_url)

options = uc.ChromeOptions()
options.add_argument('--headless=new')
driver = uc.Chrome(options = options)
#driver = uc.Chrome()
driver._web_element_cls = uc.UCWebElement
driver.get(input_url)

data = WebDriverWait(driver, 8).until(
        EC.presence_of_element_located((By.TAG_NAME, "pre"))
    )

print(data.text, file=sys.stdout)