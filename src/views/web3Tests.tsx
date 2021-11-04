import { ethers } from 'ethers';
import React, { useContext } from 'react';
import { Button, Container, H1Text } from '../components/Components';
import {GlobalContext} from '../context/GlobalState';
import NGBwrapperABI from '../artifacts/contracts/Wrappers/NGBwrapper/NGBwrapper.sol/NGBwrapper.json'
import { NgBwrapper } from '../../typechain'

const Bonds = () => {
  const { NGBwrapperAddr, FixCapitalPoolAddr } = useContext(GlobalContext);

  const deposit = async () => {
    if (typeof (window as any).ethereum !== 'undefined') {
      const provider = new ethers.providers.Web3Provider((window as any).ethereum)
      const contract = new ethers.Contract(
        NGBwrapperAddr, 
        NGBwrapperABI.abi, 
        provider
      ) as NgBwrapper
      contract.approve(FixCapitalPoolAddr, '100000')
    }    
  }

  return (
    <Container>
      {/* <H1Text white>
        Browse Bonds Page
      </H1Text> */}
      <Button onClick={deposit}>Test Deposit</Button>
    </Container>
  );
};
  
export default Bonds;