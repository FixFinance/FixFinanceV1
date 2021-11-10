import React from 'react';
import { Container, H1Text, H3Text } from '../components/Components';
import { useWeb3React } from '@web3-react/core';
import { Web3Provider } from '@ethersproject/providers';
  
const About = () => {
  const {
    account,
    library,
    chainId,
    active,
    connector,
  } = useWeb3React<Web3Provider>();

  console.log("STEVENDEBUG account ", account);
  
  
  return (
    <Container>
      {/* <H1Text white>
        Browse Bonds Page
      </H1Text> */}
      <H3Text white>{account}</H3Text>
      <H3Text white>{chainId}</H3Text>
    </Container>
  );
};
  
export default About;