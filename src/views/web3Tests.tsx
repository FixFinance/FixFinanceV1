import { ethers } from 'ethers';
import React, { useContext } from 'react';
import { Button, Container, H1Text } from '../components/Components';
import {GlobalContext} from '../context/GlobalState';
import NGBwrapperABI from '../artifacts/contracts/Wrappers/NGBwrapper/NGBwrapper.sol/NGBwrapper.json'
import { NgBwrapper } from '../../typechain'

const Bonds = () => {
  const { NGBwrapperAddr, FixCapitalPoolAddr } = useContext(GlobalContext);

  const deposit = async () => {
    // @ts-ignore
    if (typeof (window).ethereum !== 'undefined') {
      // @ts-ignore
      const provider = new ethers.providers.Web3Provider(window.ethereum)
      // @ts-ignore
      const contract = new ethers.Contract(NGBwrapperAddr, NGBwrapperABI.abi, provider) as NgBwrapper
      contract.approve(FixCapitalPoolAddr, '100000')
    }    
  }
  return (
    <Container>
      {/* <H1Text white>
        Browse Bonds Page
      </H1Text> */}
      <Button>Test Deposit</Button>
    </Container>
  );
};
  
export default Bonds;